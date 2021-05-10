import {Component} from './Component'
import type {Program,TypeChecker} from 'typescript'
import * as ts from 'typescript'
import { tsSymbolFlagsToKindString } from './utils'
import {Sym,Node as ImbaNode, Token as ImbaToken} from 'imba/program'

const UserPrefs = {
	imports: {
		includeCompletionsForModuleExports:true
		importModuleSpecifierPreference: "shortest"
		importModuleSpecifierEnding: "minimal"
		includePackageJsonAutoImports:"on"
		includeAutomaticOptionalChainCompletions:false
	}
}

const SymbolObject = ts.objectAllocator.getSymbolConstructor!
const TypeObject = ts.objectAllocator.getTypeConstructor!
const NodeObject = ts.objectAllocator.getNodeConstructor!
const SourceFile = ts.objectAllocator.getSourceFileConstructor!
const Signature = ts.objectAllocator.getSignatureConstructor!


const SF = ts.SymbolFlags

extend class SourceFile

	def getCompilation
		scriptSnapshot.#compilation
		
	def i2o i
		scriptSnapshot.#compilation.i2o(i)
	
	def d2o i
		scriptSnapshot.#compilation.d2o(i)
		
	def o2d i
		scriptSnapshot.#compilation.o2d(i)
		

extend class NodeObject

	# signature
	def labelSignature
		'()'

	get #sourceFile
		let curr = self
		while curr
			# console.log 'check curr',curr,SourceFile
			if curr isa SourceFile
				return curr
			curr = curr.parent
		return null
		

extend class SymbolObject

	get function?
		flags & ts.SymbolFlags.Function

	get pascal?
		let chr = escapedName.charCodeAt(0)
		return chr >= 65 && 90 >= chr

	get modifier?
		parent and parent.escapedName.indexOf('EventModifiers') >= 0

	get tagname?
		component? or parent and (/ImbaHTMLTags|HTMLElementTagNameMap/).test(parent.escapedName)

	get mapped?
		parent and (/HTMLElementTagNameMap|GlobalEventHandlersEventMap/).test(parent.escapedName)

	get component?
		escapedName.indexOf('$$TAG$$') > 0

	get localcomponent?
		component? and pascal?

	get typeName
		if mapped?
			declarations[0].type.typeName.escapedText
		else
			''

	get sourceFile
		if component?
			valueDeclaration.#sourceFile
		else
			null

	get details
		let name = escapedName
		let meta = #meta ||= {}
		if name.indexOf('$$TAG$$') > 0
			meta.component = yes
			meta.tag = yes
			name = name.slice(0,-7).replace(/\_/g,'-')
		if name.indexOf('_$SYM$_') == 0
			name = name.split("_$SYM$_").join("#")
			meta.internal = yes
		meta.name = name
		return meta
		
	get internal?
		escapedName.indexOf("__@") == 0

	get label
		details.name

	get typeSymbol
		type..symbol or self

	def doctag name
		#doctags ||= getJsDocTags!
		for item in #doctags
			if item.name == name
				return item.text or true
		return null

	def doctags query = /.*/
		#doctags ||= getJsDocTags!
		#doctags.filter do(item)
			let match = item.name + ' ' + item.text or ''
			!!query.test(match)

	def parametersToString
		if let decl = valueDeclaration
			return '' if !decl.parameters

			let pars = decl.parameters.map do
					let out = $1.name.escapedText
					out += '?' if $1.questionToken
					return out

			return '(' + pars.join(', ') + ')'
		return ''

extend class Signature
	def toImbaTypeString
		let parts = []
		for item in parameters
			let name = item.escapedName
			let typ = item.type and checker.typeToString(item.type) or ''
			parts.push(name)
		return '(' + parts.join(', ') + ')'

extend class TypeObject
	def parametersToString
		# let str = checker.typeToString(item.type)
		# if callSignatures[0]
		if symbol
			return symbol.parametersToString!

		return ''


# wrapper for ts symbol / type with added info
 

export class ProgramSnapshot < Component

	checker\TypeChecker

	constructor program, file = null
		super()
		program = program
		checker = program.getTypeChecker!
		self.file = #file = file
		#blank = file or program.getSourceFiles()[0]
		if file
			self.sourceFile = program.getSourceFileByPath(file.fileName)
		#typeCache = {}
		
		self.SF = SF
		self.ts = ts

	# get checker
	#	#checker ||= program.getTypeChecker!

	get basetypes
		#basetypes ||= {
			string: checker.getStringType!
			number: checker.getNumberType!
			any: checker.getAnyType!
			void: checker.getVoidType!
			"undefined": checker.getUndefinedType!
		}
		
	def getLocalTagsInScope
		let symbols = checker.getSymbolsInScope(sourceFile,32)
		for s in symbols
			type(s)
		symbols = symbols.filter do(s)
			let key = type([s,'prototype'])
			key and key.getProperty('suspend')
		return symbols
		# symbols = symbols.filter do(item)
		#	let type = typ(item)
		#	# member(item,'')

	def getSymbolInfo symbol
		symbol = sym(symbol)
		let out = ts.SymbolDisplay.getSymbolDisplayPartsDocumentationAndSymbolKind(checker,symbol,sourceFile,sourceFile,sourceFile)
		return out
	
	def getTagSymbol name
		let symbol
		if util.isPascal(name)
			symbol = local(name)
		else
			# check in global html types
			symbol = sym("HTMLElementTagNameMap.{name}")
			
			unless symbol
				let key = name.replace(/\-/g,'_') + '$$TAG$$'
				symbol = sym("globalThis.{key}")

		return symbol
		

	def arraytype inner
		checker.createArrayType(inner or basetypes.any)

	def resolve name,types = SF.All
		let sym = checker.resolveName(name,#location or loc(#file),symbolFlags(types),false)
		return sym
		
	def parseType string, token, returnAst = no
		
		string = string.slice(1) if string[0] == '\\'
		if let cached = #typeCache[string]
			return cached
		
		let ast
		try
			ast = ts.parseJSDocTypeExpressionForTests(string,0,string.length).jsDocTypeExpression.type
			ast.resolved = resolveTypeExpression(ast,{text: string},token)
			return ast if returnAst
			return #typeCache[string] = ast.resolved
		catch e
			yes
			# console.log 'parseType error',e,ast
	
	def resolveTypeExpression expr, source, ctx
		let val = expr.getText(source)
		
		if expr.elements
			let types = expr.elements.map do resolveTypeExpression($1,source,ctx)
			return checker.createArrayType(types[0])
		
		if expr.elementType
			let type = resolveTypeExpression(expr.elementType,source,ctx)
			return checker.createArrayType(type)
		
		if expr.types
			let types = expr.types.map do resolveTypeExpression($1,source,ctx)
			# console.log 'type unions',types
			return checker.getUnionType(types)
		if expr.typeName
			let typ = local(expr.typeName.escapedText,#file,'Type')
			if typ
				return checker.getDeclaredTypeOfSymbol(typ)
				return type(typ)
		elif basetypes[val]
			return basetypes[val]
		
		
	

	def local name, target = #location, types = SF.All
		let sym = checker.resolveName(name,loc(target or #file),symbolFlags(types),false)
		return sym

	def symbolFlags val
		if typeof val == 'string'
			val = SF[val]
		return val

	def signature item
		let typ = type(item)
		let signatures = checker.getSignaturesOfType(typ,0)
		return signatures[0]

	def string item
		let parts
		if item isa Signature
			parts = ts.signatureToDisplayParts(checker,item)
		
		if parts isa Array
			return util.displayPartsToString(parts)
		return ''

	def fileRef value
		return undefined unless value
		
		if value.fileName
			value = value.fileName

		if typeof value == 'string'
			program.getSourceFileByPath(value)
		else
			value
			
	set location value
		let item = loc(value)
		#location = item
	
	get location
		#location

	def loc item
		console.l
		return undefined unless item
		if typeof item == 'number'
			return ts.findPrecedingToken(item,loc(#file))
		if item.fileName
			return program.getSourceFileByPath(item.fileName)
		if item isa SymbolObject
			return item.valueDeclaration
		return item


	def type item
		if typeof item == 'string'
			if item.indexOf('.') >= 0
				item = item.split('.')
			else
				item = resolve(item)

		if item isa Array
			let base = type(item[0])
			for entry,i in item when i > 0
				base = type(member(base,entry))
			item = base

		if item isa SymbolObject
			# console.log 'get the declared type of the symbol',item,item.flags
			if item.flags & SF.Interface
				
				item.type ||= checker.getDeclaredTypeOfSymbol(item)
			item.type ||= checker.getTypeOfSymbolAtLocation(item,loc(#file or #blank))
			return item.type

		if item isa TypeObject
			return item

		if item isa Signature
			return item.getReturnType!

	def sym item
		if typeof item == 'string'
			if item.indexOf('.') >= 0
				item = item.split('.')
			else
				item = resolve(item)

		if item isa Array
			let base = sym(item[0])
			for entry,i in item when i > 0
				base = sym(member(base,entry))
			item = base

		if item isa SymbolObject
			return item

		if item isa TypeObject and item.symbol
			return item.symbol

	def locals source = #file
		let file = fileRef(source)
		let locals = file.locals.values!
		return Array.from(locals)
	
	def props item, withTypes = no
		let typ = type(item)
		return [] unless typ

		let props = typ.getProperties!
		if withTypes
			for item in props
				type(item)
		return props

	def propnames item
		let values = type(item).getProperties!
		values.map do $1.escapedName
	
	def getSelf loc = #location
		# with imba context, find the closest tag/class declaration
		# keyword. Find its location relative to the previously compiled
		# version of the typescript snapshot.
		# get the symbol and type from there.
		# possibly access prototype or not based on field
		# f0.checker.checker.getSymbolAtLocation(f0.checker.loc(25))
		yes
		
		# checker.getSymbolAtLocation(f0.checker.loc(25))

	def member item, name
		return unless item

		if typeof name == 'number'
			name = String(name)

		# if name isa Array
		#	console.log 'access the signature of this type!!',item,name

		# console.log 'member',item,name
		let key = name.replace(/\!$/,'')
		let typ = type(item)
		let sym = typ.getProperty(key)
		
		if key == '__@iterable'
			# console.log "CHECK TYPE",item,name
			let resolvedType = checker.getApparentType(typ)
			return null unless resolvedType.members
			sym = resolvedType.members.get('__@iterator')
			return type(signature(sym)).resolvedTypeArguments[0]
			#  iter.getCallSignatures()[0].getReturnType()
			
		if sym == undefined
			let resolvedType = checker.getApparentType(typ)
			return null unless resolvedType.members
			sym = resolvedType.members.get(name)
			
			if name.match(/^\d+$/)
				sym ||= typ.getNumberIndexType!
			else
				sym ||= typ.getStringIndexType!

		if key !== name
			sym = signature(sym)
		return sym

	def wrap value
		value

	def inspect value
		# for item in value
		#	devlog item.label,item
		value

	get globals do resolve('globalThis')
	get win do resolve('window')
	get doc do resolve('document')

	def path path, base = null
		yes
		
	def getNode input
		if input isa ImbaToken
			let span = input.span
			let offset = sourceFile.d2o(span.offset + span.length)
			# console.log 'get node at',span,offset
			return loc(offset)
		return input
		
	def getThisContainer node
		# if node is an imba node
		if node isa ImbaToken
			let token = getNode(node)
			# console.log 'found container loc?!',node,token
			node = token
		
		ts.getThisContainer(node,false)
		

	def resolvePath tok, doc, loc = null
		

		if tok isa Array
			return tok.map do resolvePath($1,doc)
		
		if typeof tok == 'number' or typeof tok == 'string'
			
			if typeof tok == 'string' and tok[0] == '\\'
				return parseType(tok,null)

			return tok

		if tok isa ImbaNode
			let node = tok
			if tok.type == 'type'
				let val = String(tok)
				return parseType(val,tok)
				# console.log 'DATATYPE',tok.datatype,val
				# we do need to resolve the type to
				# if basetypes[val.slice(1)]
				#	return basetypes[val.slice(1)]
			
			if tok.match('value')
				let end = tok.end.prev
				while end and end.match('br')
					end = end.prev
				# end = end.prev if end.match('br')
				tok = end
				let typ = resolvePath(tok,doc,tok)
				console.log 'resolved type',typ
				if node.start.next.match('keyword.new')
					typ = [typ,'prototype']
				return typ
				
			# console.log 'checking imba node!!!',tok
		
		let sym = tok.symbol
		let typ = tok.type

		if tok isa Sym
			let typ = tok.datatype
			if typ
				return resolvePath(typ,doc)
				
			if tok.#tsym
				return tok.#tsym

			if tok.body
				# doesnt make sense
				return resolveType(tok.body,doc)
				
			return basetypes.any

		let value = tok.pops

		if value
			if value.match('index')
				return [resolvePath(value.start.prev),'0']

			if value.match('args')
				
				let res = type(signature(resolvePath(value.start.prev),[]))
				devlog 'token match args!!!',res
				return res

			if value.match('array')
				# console.log 'found array!!!',tok.pops
				return arraytype(basetypes.any)

		if tok.match('tag.event.start')
			return 'ImbaEvents'

		if tok.match('tag.event.name')
			# maybe prefix makes sense to keep after all now?
			return ['ImbaEvents',tok.value]

		if tok.match('tag.event-modifier.start')
			# maybe prefix makes sense to keep after all now?
			return [['ImbaEvents',tok.context.name],'MODIFIERS']
			# return ['ImbaEvents',tok.value]
		
		# if this is a call
		if typ == ')' and tok.start
			return [resolvePath(tok.start.prev),'!']

		if tok.match('number')
			return basetypes.number

		elif tok.match('string')
			return basetypes.string

		if tok.match('operator.access')
			devlog 'resolve before operator.oacecss',tok.prev
			return resolvePath(tok.prev,doc)

		if tok.type == 'self'
			return tok.context.selfScope.selfPath
		
		if tok.match('identifier.special')
			let argIndex = tok.value.match(/^\$\d+$/) and parseInt(tok.value.slice(1)) - 1
			let container = getThisContainer(tok)
			# console.warn "found arg index!!!",argIndex,container
			if argIndex == -1
				return resolve('arguments',container)

			return checker.getContextualTypeForArgumentAtIndex(container,argIndex)
			

		if tok.match('identifier')
			# what if it is inside an object that is flagged as an assignment?			
			if tok.value == 'global'
				return 'globalThis'

			if !sym
				let scope = tok.context.selfScope

				if tok.value == 'self'
					return scope.selfPath

				let accessor = tok.value[0] == tok.value[0].toLowerCase!
				if accessor
					return [scope.selfPath,tok.value]
				else
					return type(self.local(tok.value))
			
			# type should be resolved at the location it is in(!)
			
			return resolveType(sym,doc,tok)

		if tok.match('accessor')
			# let lft = tok.prev.prev
			return [resolvePath(tok.prev,doc),tok.value]

	def resolveType tok, doc
		let paths = resolvePath(tok,doc)
		# console.log 'resolving paths',paths
		return type(paths)
		
		
	def resolveAutoImport name, source
		let tls = file.ils.tls
		let loc = file.emittedCompilation.obody.length
		return tls.getCompletionEntryDetails(file.fileName,loc,name,{},source,UserPrefs.imports)