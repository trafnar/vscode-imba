import {Component} from './Component'
import {CompletionItemKind,DiagnosticSeverity,SymbolKind,Location,LocationLink} from 'vscode-languageserver-types'
# import {Location} from 'vscode-languageserver'

import * as util from './utils'
import { FullTextDocument } from './FullTextDocument'
import { items } from '../../test/data'
import {Keywords,KeywordTypes,CompletionTypes,Sym,SymbolFlags} from 'imba/program'
import {Diagnostics, Diagnostic, DiagnosticKind} from './Diagnostics'
import * as ts from 'typescript'
import type {TypeNode,TypeFlags} from 'typescript'
import type {LanguageServer} from './LanguageServer'
import system from './system'
import { CompletionsContext } from './Completions'
import { ProgramSnapshot } from './Checker'
import Compilation from './Compilation'

const imbac = require 'imba/compiler'
const imba1c = require '../imba1.compiler.js'

let imbaOptions = {
	target: 'tsc'
	platform: 'tsc'
	imbaPath: null
	silent: yes
	sourcemap: 'hidden'
}

###
Represents the combination of an imba-file and its compiled ts/js
with functionality to map locations back and forth between the two
###
export class File < Component
	prop symbols = []
	removed = no

	static def build ils,src
		let ext = util.t2iPath(src.slice(src.lastIndexOf('.')))

		let types = {
			'.json': JSONFile
			'.imba': ImbaFile
			'.imba1': Imba1File
			'.svg': SVGFile
			'.png': ImageFile
			'.jpg': ImageFile
			'.jpeg': ImageFile
			'.gif': ImageFile
			'.html': HTMLFile
		}

		let cls = types[ext] or File
		return new cls(ils,src)

	def constructor program\LanguageServer, path
		super
		isLegacy = no
		version = 1
		self.program = program
		fileName = util.t2iPath(path)
		program.files[fileName] = self
		program.files[tfileName] = self
		program.files.push(self)
		#compilations = []
		#compilationMap = {}

	get shouldEmitDiagnostics
		no
	
	get ils
		program

	get tls
		isLegacy ? null : program.tls

	get uri
		util.pathToUri(fileName)

	get document
		program.documents.get(uri)

	get tfileName
		util.i2tPath(fileName)

	get tsPath
		tfileName
		
	get tlsfile
		ils.getProgram!.getSourceFile(tfileName)

	get tscriptKind
		ts.ScriptKind.JS

	get imbaPath
		fileName

	get workspaceSymbols
		[]

	def getCompiledBody
		""
		# String(system.readFile(fileName))

	def getSourceBody
		doc.getText!

	def getScriptSnapshot
		#snapshot ||= ts.ScriptSnapshot.fromString(getCompiledBody!)


	def textSpanToRange
		return {start: {line:0,character:0},end: {line:0,character:0}}

	def textSpanToText
		return ""

	def dispose
		self

	def onDidChangeTextEditorSelection params
		return
		
	def didLoad
		log 'didLoad',fileName
		yes
		
	def didOpen
		yes
		
	def didChange
		yes
	
	def didSave
		yes
		

export class ImbaFile < File

	def constructor program\LanguageServer, path
		super
		isLegacy = fileName.indexOf('.imba1') > 0 or program.isLegacy

		if program && !program.rootFiles.includes(tfileName) and !isLegacy
			program.rootFiles.push(tfileName)

		logLevel = fileName.indexOf('Diagnostics') >= 0 ? 3 : 0
		diagnostics = new Diagnostics(self)
		#emptySnapshot = ts.ScriptSnapshot.fromString('export {}')
		#emptySnapshot.iversion = 0

		emitted = {}
		times = {}
		_isTyping = no
		invalidate!
		self
	
	get shouldEmitDiagnostics
		yes

	get doc
		$doc ||= FullTextDocument.create(uri,'imba',0,system.readFile(fileName))
	
	get idoc
		doc.tokens

	get isTyping
		_isTyping

	set isTyping value
		if _isTyping =? value
			yes

	def getScriptSnapshot
		let item = currentCompilation
		return item.js or #emptySnapshot
		
	def getCompiledBody
		getScriptSnapshot!.text
		# include potential diagnostics from imba compiler in last compilation
		# include ts diagnostics from last emitted compilation

	def didOpen doc
		$doc = doc
		if doc.tokens
			isLegacy = doc.tokens.isLegacy
		times.opened = Date.now!
		emitFile(true)
		log 'didOpen',uri,!!tls
		sendDiagnostics!

	def didChange doc, event = null
		$doc = doc
		version = doc.version
		cache.contexts = {}
		
		# diagnostics.sync!
		times.edited = Date.now!
		
		console.log 'didChange',doc.version
		sendDiagnostics!

		if version > 1
			isTyping = yes
			$delay('emitFile',5000)
		else
			$delay('emitFile',10)
		# console.log 'didChange'
		# $clearSyntacticErrors! # only if our regions have changed?!?

	def didSave doc
		savedContent = doc.getText!
		emitFile(true)
		# diagnostics.sync!
		times.saved = Date.now!
		isTyping = no
	
	def didLoad
		if times.opened
			sendDiagnostics!
		self

	def dispose
		delete program.files[fileName]
		let idx = program.files.indexOf(self)
		program.files.splice(idx,1) if idx >= 0

		idx = program.rootFiles.indexOf(fileName)
		program.rootFiles.splice(idx,1) if idx >= 0
		program.invalidate!
		self

	def emitFile refresh = yes
		$cancel('emitFile')
		
		let emit = scheduleCompilation!
		emit.compile!
		
		if emit.js
			if emit.#emitted =? yes
				devlog 'emitting file to ts',fileName
				program.invalidate!
				if tls
					tls.getEmitOutput(fileName)
				sendDiagnostics!
		return self
		
		let content = doc.getText!
		if content != lastEmitContent
			lastEmitContent = content
			invalidate!
			version++
			log 'emitFile',uri,version,isLegacy
			program.invalidate! unless isLegacy
		
		if tls
			tls.getEmitOutput(fileName)
			#checker = null
			getDiagnostics! if refresh
		else
			compile!
		return self

	def updateDiagnostics items\Diagnostic[] = [], versions
		let kind = DiagnosticKind.TypeScript | DiagnosticKind.Semantic
		unless result and result.error
			diagnostics.update(kind,items,versions)
		return self
		
	def trySemanticDiagnostics
		return [] unless tls
		let kind = DiagnosticKind.TypeScript | DiagnosticKind.Semantic
		let entries = util.time(&,'diag') do tls.getSemanticDiagnostics(fileName)
		devlog 'diagnostics',fileName,entries
		# return entries
		let items = entries.map do Diagnostic.fromTypeScript(kind,$1,self)
		return items
		
	def getCompilerDiagnostics
		let last = lastCompilation
		last.diagnostics

	def getAllDiagnostics
		let items = []
		util.time(&,'calc diagnostics') do
			items.push(...trySemanticDiagnostics!)
			items.push(...getCompilerDiagnostics!)
		return items
		
	def sendDiagnostics
		let all = getAllDiagnostics!
		let payload = JSON.stringify(all.filter(do !$1.hidden? ))
		if #sentDiagnostics =? payload
			ils.connection.sendDiagnostics(uri: uri, diagnostics: JSON.parse(payload))
		return all

	# how is this converting?
	def positionAt offset
		doc.positionAt(offset)

	def offsetAt position
		return position if typeof position == 'number'
		doc.offsetAt(position)

	def rangeAt start, end
		idoc.rangeAt(start,end)

	# remove compiled output etc
	def invalidate
		result = null
		cache = {
			srclocs: {}
			genlocs: {}
			contexts: {}
			symbols: null
		}
		self
		
	def scheduleCompilation
		let item = #compilationMap[idoc.version] ||= new Compilation(self)
		#compilations.unshift(item) unless #compilations.indexOf(item) >= 0
		return item
		
	get currentCompilation
		let curr = #compilations.find(do $1.js)
		curr ||= scheduleCompilation!.compile!
		return curr
	
	get emittedCompilation
		#compilations.find(do $1.js)
		
	get lastCompilation
		#compilations.find(do $1.done)
		
	set compilation value
		yes
	
	get compilations
		#compilations

	def compile
		return if isLegacy

		unless result
			let body = doc.getText!
			let iversion = idoc.version
			let opts = Object.assign({},imbaOptions,{
				filename: fileName
				sourcePath: fileName
			})
			let res = null

			try
				let compiler = isLegacy ? imba1c : imbac
				res = util.time(&,"{fileName} compiled in") do
					compiler.compile(body,opts)
			catch e
				
				let loc = e.loc && e.loc()
				let range = loc && {
					offset: loc[0]
					length: loc[1] - loc[0]
				}

				let err = {
					severity: DiagnosticSeverity.Error
					message: e.message
					range: range
				}
				diagnostics.update(DiagnosticKind.Compiler,[err])
				result = {error: err}
				js ||= 'export {};\n\n'
				jsSnapshot ||= ts.ScriptSnapshot.fromString(js)
				return self

			diagnostics.update(DiagnosticKind.Compiler,res.diagnostics or [])

			if res.errors && res.errors.length
				# even if there are errors, should we not remember the last compiled version?
				# devlog "compile error!!!",res.errors
				# Should rather keep the last successfully compiled version?
				js ||= 'export {};\n\n'
				jsSnapshot ||= ts.ScriptSnapshot.fromString(js)
				result = {error: res.errors[0]}
				return
			# diagnostics.update(DiagnosticKind.Compiler,[])

			# potential memory leak?
			result = res
			locs = res.locs

			if locs
				locs.version = iversion
	
			js = res.js.replace(/\$CARET\$/g,'valueOf')
			tsVersion = iversion
			jsSnapshot = ts.ScriptSnapshot.fromString(js)
			jsSnapshot.version = iversion
			$indexWorkspaceSymbols!

		return self
		
	def $indexWorkspaceSymbols
		cache.symbols ||= util.fastExtractSymbols(doc.getText!,fileName)
		cache.workspaceSymbols ||= cache.symbols.map do(sym)
			sym.location = Location.create(uri,sym.span)
			sym.#file = self
			sym

		return self
	
	get workspaceSymbols
		$indexWorkspaceSymbols!
		return cache.workspaceSymbols

	def sourceRangeAt start, end
		for [ts0,ts1,imba0,imba1] in locs.spans
			if start == ts0 and end == ts1
				return idoc.rangeAt(imba0,imba1)
		return null

	def originalRangesFor jsloc
		locs.spans.filter do |pair|
			jsloc >= pair[0] and pair[1] >= jsloc

	def originalRangeFor {start,length,end = null}
		if end == null
			end = start + length
			
		let snap = currentCompilation
		return snap.o2dRange(start,end)

		let starts = []
		let ends = []
		let hit = null

		for span in locs.spans
			if start == span[0]
				starts.push(span)
			if end == span[1]
				ends.push(span)

			if start == span[0] and end == span[1]
				break hit = span
		
		if !hit and starts.length and ends.length
			hit = [0,0,starts[0][2],ends[0][3]]

		if hit
			return idoc.rangeAt(hit[2],hit[3])
		return null

	# need a better converter
	def originalLocFor jsloc
		let val = cache.srclocs[jsloc]
		if val != undefined
			return val

		let spans = originalRangesFor(jsloc)

		if let span = spans[0]
			let into = (jsloc - span[0]) / (span[1] - span[0])
			let offset = Math.floor(into * (span[3] - span[2]))
			# console.log 'found originalLocFor',jsloc,spans
			if span[0] == jsloc
				val = span[2]
			elif span[1] == jsloc
				val = span[3]
			else
				val = span[2] + offset

		return cache.srclocs[jsloc] = val

	def generatedRangesFor loc
		return [] unless locs and locs.spans

		locs.spans.filter do |pair|
			loc >= pair[2] and pair[3] >= loc

	def generatedLocFor loc
		let spans = generatedRangesFor(loc)
		if let span = spans[0]
			let into = (loc - span[2]) / (span[3] - span[2])
			let offset = Math.floor(into * (span[1] - span[0]))
			# console.log 'found generatedLocFor',loc,spans
			if loc == span[2]
				return span[0]
			elif loc == span[3]
				return span[1]
			else
				return span[0] + offset
		return null

	# need to specify that this converts from typescript
	def textSpanToRange span
		if span.length == 0
			if span.start == 0
				return idoc.rangeAt(0,0)

			return idoc.rangeAt(originalLocFor(span.start))
			let pos = doc.positionAt(originalLocFor(span.start))
			return {start: pos,end: pos}
		let range = originalRangeFor(span)
		if range
			# let start = @originalLocFor(span.start)
			# let end = @originalLocFor(span.start + span.length)
			# console.log 'textSpanToRange',span,start,end,@locs and @locs.generated
			{start: doc.positionAt(range.start), end: doc.positionAt(range.end)}

	def textSpanToText span
		let start = originalLocFor(span.start)
		let end = originalLocFor(span.start + span.length)
		return doc.getText!.slice(start,end)

	def getDiagnostics
		return unless tls and result and !result.error

		let entries = tls.getSemanticDiagnostics(tsPath)
		let kind = DiagnosticKind.TypeScript | DiagnosticKind.Semantic
		diagnostics.update(kind,entries)
		self
	
	def getDefinitionAtPosition pos
		return if isLegacy
		let offset = offsetAt(pos)
		
		let snap = currentCompilation
		let oloc = snap.d2o(offset)
		let ctx = idoc.getContextAtOffset(offset)
		
		log 'getDefinitionAtPosition',offset,oloc

		let info = tls.getDefinitionAndBoundSpan(fileName,oloc) or {definitions:[]}
		
		return unless info.textSpan
		
		let sourceSpan = snap.o2dRange(info.textSpan.start,info.textSpan.start + info.textSpan.length)
		let sourceText = sourceSpan.getText(idoc.content)
		devlog 'definitions',info,sourceSpan,sourceText
		# let sourceSpan = originalRangeFor(info.textSpan)
		# let sourceText = doc.getText!.slice(sourceSpan.start,sourceSpan.end)
		let isLink = sourceText and sourceText.indexOf('-') >= 0

		devlog 'get definition',uri,pos,offset,oloc,info,sourceSpan,sourceText,isLink
		let defs = for item in info.definitions
			# console.log 'get definition',item
			let ifile = ils.files[item.fileName]
			if ifile
				
				let textSpan = ifile.originalRangeFor(item.textSpan)
				let span = item.contextSpan ? ifile.originalRangeFor(item.contextSpan) : textSpan
				span ||= textSpan
				devlog 'definition',item,ifile,textSpan,span,sourceSpan,sourceText

				if item.containerName == 'globalThis' and item.name.indexOf('$$TAG$$') >= 0
					span = {
						start: {line: textSpan.start.line, character: 0}
						end: {line: textSpan.start.line + 1, character: 0}
					}
				
				devlog 'definition',item,textSpan,span,item.kind
				if item.kind == 'module'
					textSpan = {start: {line:0,character:0},end: {line:0,character:0}}
					console.log 'LocationLink',ifile.uri,textSpan,sourceSpan
					LocationLink.create(ifile.uri,textSpan,textSpan,sourceSpan)
					# Location.create(ifile.uri,)
				elif isLink
					LocationLink.create(ifile.uri,textSpan,span,sourceSpan)
				else
					Location.create(ifile.uri,textSpan)

			elif item.name == '__new' and info.definitions.length > 1
				continue
			else
				let span = util.textSpanToRange(item.contextSpan or item.textSpan,item.fileName,tls)
				if isLink
					LocationLink.create(util.pathToUri(item.fileName),span,span,sourceSpan)
				else
					Location.create(util.pathToUri(item.fileName),span)
		return defs

	def getDefinitionAtOffset offset
		getDefinitionAtPosition(positionAt(offset))

	
	def getAdjustmentEdits pos, amount = 1
		let loc =  offsetAt(pos)
		let edit = idoc.adjustmentAtOffset(loc,amount)
		return edit

	def getQuickInfoAtPosition pos
		return if isLegacy
		
		let dloc = offsetAt(pos)
		
		let snap = currentCompilation
		let ctx = idoc.getContextAtOffset(dloc)

		# see if we should move one step ahead
		if ctx.after.token == '' and !ctx.before.character.match(/\w/)
			if ctx.after.character.match(/[\w\$\@\#\-]/)
				ctx = idoc.getContextAtOffset(dloc + 1)

		let grp = ctx.group
		let tok = ctx.token or {match: (do no)}

		if ctx.token and !ctx.token.value
			log 'token without value',ctx.token

		let range = idoc.getTokenRange(ctx.token)
		let g = {}

		# console.log 'the context we got here',ctx.mode,range
		try
			let info = null
			let symbol = null

			if tok.match("tag.flag")
				info = "```imba\n<el class='... {tok.value} ...'>\n```"

			if tok.match("tag.id")
				info = "```imba\n<el id='{tok.value.slice(1)}'>\n```"

			if tok.match("style.property.modifier") or tok.match("style.selector.modifier")
				let [m,pre,post] = tok.value.match(/^(@|\.+)([\w\-\d]*)$/)
				devlog 'matching!!',m,pre,post

				if pre == '@' or pre == ''
					symbol = getSymbolAtPath("global.imba.stylemodifiers.{post}")
				elif pre == '.'
					info = "Style only applies when element has '{post}' class"
				elif pre == '..'
					info = "Style only applies when a parent of element has has '{post}' class"
			
			g.listener = grp.closest('listener')
			g.el = grp.closest('tag')
			let csspropkey = g.csspropkey = grp.closest('stylepropkey')
			let cssprop = g.cssprop = grp.closest('styleprop')

			if csspropkey and !symbol and !info
				devlog 'csspropkey info!!',ctx,csspropkey.modifier,csspropkey.propertyName
				info = ils.entities.getCSSInfo(ctx)

			if tok.match('style.value')
				info = ils.entities.getCSSValueInfo(tok.value,cssprop.propertyName,ctx)

			if tok.match('tag.event.name')
				let name = tok.value.replace('@','')
				# devlog 'tagevent name',name,grp,g.el.name,g.listener.name
				let path = "global.imba.types.events.{name}|__unknown"
				symbol = getSymbolAtPath(path)
				# let info = ils.entities.getTagEventInfo(g.listener.name,g.el.name)
				# devlog info
				# return {range: range, contents: info.description} if info

			if tok.match('tag.event-modifier')
				let name = tok.value.replace('.','')
				let path = "global.imba.types.events.{g.listener.name}|__unknown.MODIFIERS.{name}"
				symbol = getSymbolAtPath(path)			

			if !info and symbol
				let details = symbol.getCompletionDetails()
				let md = util.detailsToMarkdown(details)
				info = {markdown: md}
			
			if typeof info == 'string'
				info = {markdown: info}

			if info and info.markdown
				return {range: range, contents: {kind: 'markdown', value: info.markdown}}

			# don't fall back to typescript if we're in style mode
			if (grp.closest('style') or grp.closest('rule')) && !grp.closest('styleinterpolation')
				return {}
		catch e
			devlog 'error in getQuickInfo',e
			# get quick info via typescript
		
		let oloc = snap.d2o(dloc)
		let tinfo = util.time(&,'quickinfo') do ils.tls.getQuickInfoAtPosition(fileName,oloc)
		devlog 'getQuickInfoAtPosition',dloc,oloc,tinfo
		
		if tinfo
			let out = {
				range: snap.o2d(tinfo.textSpan)
				contents: [{
					value: util.displayPartsToString(tinfo.displayParts)
					language: 'typescript'
				}]
			}

			if tinfo.documentation
				out.contents.push(value: util.displayPartsToString(tinfo.documentation), language: 'text')
			return out

		return null

	get checker
		#checker ||= new ProgramSnapshot(ils.getProgram!,self)

	def getTypeContext
		let prog = ils.getProgram!
		return {file: prog.getSourceFile(tsPath), checker: prog.getTypeChecker!, program: prog}

	def getSelfAtOffset offset
		let context = idoc.getContextAtOffset(offset)
		let scope = context.scope.selfScope
		let base = scope.closest do $1.class?

		let {file,checker,program} = getTypeContext!
		let type = null

		if base
			if let sym = file.locals.get(base.path)
				type = checker.getTypeOfSymbolAtLocation(sym,file)
				type.#path = "{base.path}"
		
		if type and scope.member? and !scope.static?
			let sym = type.getProperty('prototype')
			type = checker.getTypeOfSymbolAtLocation(sym,file)
			type.#checker = checker
			type.#symbol = sym
			type.#file = file
			type.#path = "{base.path}.prototype"

		return type

	def getSymbolAtPath path,resolveGlobal = yes
		devlog "get symbol {path}"
		let {file,checker,program} = getTypeContext!
		let type = null
		let target = null
		let parts = path.split('.')

		let getCompletionDetails = do
			ts.Completions.createCompletionDetailsForSymbol(this,checker,file,file)
		
		while let part = parts.shift!
			let alternatives = part.split('|')
			part = alternatives.shift!
			let sym = null
			if part.match(/^\<[\w\-]+\>$/)
				let name = part.slice(1,-1)
				let pascal = util.pascalCase(name)

				if name == pascal
					part = name
					parts.unshift('prototype')
					# sym = file.locals.get(name)
				else
					sym ||= getSymbolAtPath("global.imba.types.html.tags.{name}")
					sym ||= getSymbolAtPath("global.{name.replace(/\-/g,'_')}$$TAG$$.prototype")

			sym ||= target ? target.#type.getProperty(part) : file.locals.get(part)

			if !target and !sym and (part == 'global' or resolveGlobal)
				part = 'globalThis' if part == 'global'
				sym = checker.resolveName(part,undefined,ts.SymbolFlags.Value,false)


			if !sym and alternatives.length
				parts.unshift alternatives.join('|')
				continue

			return null unless sym

			let type = sym.#type = checker.getTypeOfSymbolAtLocation(sym,file)
			sym.#parent = target
			sym.getCompletionDetails = getCompletionDetails
			sym.#type.getCompletionDetails = getCompletionDetails.bind(sym)
			type.#path = path
			target = sym
		
		return target

	def getPropertiesAtPath path, ...filters
		let type = getTypeAtPath(path)
		return [] unless type

		let props = type.getApparentProperties!
		
		for filter in filters
			if filter isa Array
				props = props.filter do(item) filter.some do $1(item)
			elif filter isa Function
				props = props.filter(filter)
			elif filter isa RegExp
				props = props.filter do !$1.escapedName.match(filter)
		
		props.keys = {}

		for item in props
			if let name = item.escapedName
				try
					props.keys[name] = item
					item.#path = "{type.#path}.{name}"
				catch e
					devlog e,props.keys,props,name
		return props

	def getTypeAtPath path
		let sym = getSymbolAtPath(path)
		
		return sym and sym.#type

	def getTypeOfSymbolAtOffset offset
		let {file,checker,program} = getTypeContext!
		let tsloc = generatedLocFor(offset)
		let tok = ts.findPrecedingToken(tsloc,file)
		let origTok = tok
		if $web$
			global.T = tok
			global.checker = checker
			global.checkerNode = origTok
		devlog 'getTypeOfSymbolAtOffset',tsloc,offset,tok

		let type = null

		let logtok = do(tok)
			devlog "tok {tok.kind}",tok,checker.getTypeAtLocation(tok)

		if tok and (tok.kind == 24 or tok.kind == 28)
			tok = tok.parent

			if tok.kind == 201
				logtok tok._children[0]
				type = checker.getTypeAtLocation(tok._children[0])
			else
				tok = tok.expression
		
		unless type
			try
				let sym = checker.getSymbolAtLocation(tok)
				type = checker.getTypeOfSymbolAtLocation(sym,file)

		if type
			type.#node = origTok
			type.#file = file
			type.#checker = checker
		return type

	def completions offset, options = {}
		let completions = new CompletionsContext(self,offset,options)
		return completions

	def getCompletionsAtOffset offset, options = {}
		unless emittedCompilation
			log 'got no working file'
			return []

		let completions = new CompletionsContext(self,offset,options)
		if $web$
			global.cl = completions
		
		let out = completions.serialize!
		# console.log 'returned completions',out
		return out

		let results = #getCompletionsAtOffset(offset,options) or []
		# return results
		return unless results
		
		let remove = []
		for item in results
			let lbl = item.label.name or item.label
			if lbl.match(/\w\$\d+$/)
				remove.push(item)
		
		results = results.filter do remove.indexOf($1) == -1
		console.log 'results from completions',results
		return results
			

	def #getCompletionsAtOffset offset, options = {}
		let items = []
		let names = new Map

		return if isLegacy	

		let ctx = idoc.getContextAtOffset(offset)

		let grp = ctx.group
		let tok = ctx.token
		let that = getSelfAtOffset(offset)
		let vars = idoc.varsAtOffset(offset,yes)
		let target = that
		let mode = null
		let suggest = ctx.suggest
		let flags = suggest.flags
		let filters = {kinds: []}
		let tsoffset = null
		let keywordFilter = 0
		let resolveLocalsPath = null
		let props = null
		let noGlobals = !!ctx.scope.class?
		let noVars = no
		let noKeywords = no
		let g = {}

		g.el = grp.closest('tag')

		let add = do(...parts)
			for item in parts
				# devlog 'add item',item.label,item
				names.set(item.label,item)
				items.push(item)
	
		# $delay('emitFile',5000)
		devlog 'completions in context',that,ctx,offset

		if $web$
			global.ct = ctx
			ctx.SELF = that
		devlog 'getCompletions',ctx.before,ctx.after,offset,options
		# console.log ils.config.config
		let t = CompletionTypes
		let opts = Object.assign({},ils.config.config.suggest,suggest)

		if tok.match('operator.equals') and tok.prev.match('tag.attr')
			let key = "global.imba.tagtypes.{g.el.tagName}.{tok.prev.value}"
			let type = getTypeAtPath(key)
			
			if type..types..length
				target = null
				for item in type.types
					add({
						label: item.value
						insertText: "'{item.value}'"
						sortText:'0'
					})
				devlog "drop target!!!",items


		# if at start of string
		if tok.match('string.open')
			target = null
			noGlobals = yes
			noKeywords = yes

			if grp.match('tagattrvalue')
				devlog 'matched tag attribute value!!',grp.tagName, grp.propertyName
				let key = "global.imba.tagtypes.{grp.tagName}.{grp.propertyName}"
				if let type = getTypeAtPath(key)
					
					for item in type.types
						add({
							label: item.value
						})
					# devlog "found type!!!",type,items


		
		if flags & t.Path
			try
				let tloc = generatedLocFor(offset)
				let res =  util.tsp2lspCompletions(tls.getCompletionsAtPosition(tfileName,tloc,{}).entries,{file:self,jsLoc:tsoffset})
				return res

		if flags & t.Type
			devlog 'complete types!!'
			let res = ils.entities.getTypesForFile(self,ctx)
			return res


		if flags & t.TagName
			
			let res = ils.entities.getTagNameCompletions(ctx.group,opts,self)
			devlog 'tagname completions!!!',res
			return res

		if flags & t.TagProp
			devlog 'TagProp completions',flags,g.el,g.el.tagName,g.el.pathName
			let key = "<{g.el.tagName}>"
			noGlobals = true
			noKeywords = true
			target = getTypeAtPath(key)
			props = getPropertiesAtPath(key,util.isAttr,/^on\w/,/__$/)
			let attrs = getPropertiesAtPath("global.imba.tagtypes.{g.el.tagName}")
			devlog 'found attributes',attrs
			# for item in attrs
			# 	if props[item.escapedName]
			# 		props[item.escapedName].#path = item.#path
			# find the element properties via other 
		
		
		if tok.match('tag.event.name') and false
			# if flags & t.TagEvent
			return ils.entities.getTagEventCompletions(ctx.group,opts)

		if tok.match('style.property.modifier') or tok.match('style.selector.modifier')
			target = getTypeAtPath('global.imba.stylemodifiers')
			props = target.getApparentProperties!
			devlog 'Style modifiers!!!',target,target.#path
		
		elif flags & t.StyleValue
			items = ils.entities.getCSSValueCompletions(ctx,opts)

			if flags & t.StyleProp
				items.push(...ils.entities.getCSSPropertyCompletions(ctx.group,opts))

			return items

		elif flags & t.StyleProp
			return ils.entities.getCSSPropertyCompletions(ctx.group,opts)

		if tok.match('tag.event.name')
			let path = "global.imba.types.events"
			devlog "get completions for",path
			target = getTypeAtPath(path)

		if tok.match('tag.event-modifier')
			let ev = grp.closest('listener')..name
			let mod = tok.value.replace('.','')
			let path = "global.imba.types.events.{ev}|click.MODIFIERS"
			devlog "get completions for",path
			target = getTypeAtPath(path)
			devlog 'event modifier completion',ev,mod,target.#path

		# completions have already started here
		if tok.match('accessor')
			tsoffset = generatedLocFor(offset - ctx.before.token.length)
			console.log 'accessor completion',tsoffset,tok.type
			# check that the ts offset is valid?
			let tscompletions = tls.getCompletionsAtPosition(fileName,tsoffset,{})
			let completions = util.tsp2lspCompletions(tscompletions.entries,{file:self,jsLoc:tsoffset})
			return completions

		# find the access chain
		if tok.match('operator.access')
			console.log 'operator.access',tok.type
			# may be worth trying to fake the lookup 
			util.time(&,'emit') do $flush('emitFile',false)
			# never fall back to tls if file has not compiled correctly!!
			tsoffset = generatedLocFor(offset)
			let tscompletions = tls.getCompletionsAtPosition(fileName,tsoffset,{})
			let completions = util.tsp2lspCompletions(tscompletions.entries,{file:self,jsLoc:tsoffset})
			return completions

		if tok.match('comment') and ctx.before.token == '#'
			# complete internal properties
			yes


		if flags == 0 and !props and !items.length
			return []

		# if we are inside a tag tree - add automatic completions for tags with autoinserted braces
		if grp.match('tagcontent') and ctx.scope.match('tagcontent')
			# cannot be inside string etc
			# devlog "IS INSIDE TAG CONTENT!!"
			noGlobals = true
			let res = ils.entities.getTagNameCompletions(ctx.group,opts,self)
			for item in res
				item.insertText = "<{item.label.name or item.label}>"
				item.sortText = '0'
				add(item)

		# if tok.match('identifier')
		#	filters.startsWith = ctx.before.token
		
		if tok.match('keyword')
			return []

		devlog 'check completion',target,ctx.scope.class?

		if target && (!ctx.scope.class? or props)
			# console.dir target, depth: 0
			devlog 'completions for target',target
			props ||= target.getApparentProperties!

			for item in props
				let name = item.escapedName
				continue if name.match(/^(__@|"|__+unknown|___)/)
				continue if name.match(/^\w+\$\d+/) # this is agenerated variable
				continue unless item.flags & ts.SymbolFlags.Value
				let kind = util.tsSymbolFlagsToKindString(item.flags)
				let data = {resolved: yes, symbolFlags: item.flags, path: fileName}

				# skip the event listener
				
				if item.#path
					data.symbolPath = item.#path

				if target.#path
					data.symbolPath ||= "{target.#path}.{name}"
					data.resolved = no

				name = name.replace(/_\$SYM\$_/g,'#')
				let label = {name: name}

				# devlog 'handle item',name,item

				if item.parent
					let pname = item.parent.escapedName
					label.qualifier = util.formatQualifier(pname)
					if pname == 'ImbaStyleModifiers'
						try label.qualifier = item.getDocumentationComment()[0].text.split('\n')[0]

				add(
					label: label
					kind: kind
					sortText: '0'
					symbol: item
					data: data
				)
		
		# if target is implicit value
		if target == that and !noKeywords
			for keyword in suggest.keywords
				add(
					label: keyword
					kind: CompletionItemKind.Keyword
					detail: 'keyword'
				)
		
		if target == that and !noGlobals
			# also show for target?

			let glob = getTypeAtPath('global')
			for item in glob.getProperties!
				let name = item.escapedName
				continue unless name.match(/^[A-Z]/)
				
				add(
					label: name
					kind: CompletionItemKind.Variable
					sortText: '2'
					symbol: item
				)
			
			unless noVars
				for variable in vars
					let sym = variable
					let name = variable.name
					if variable.type == 'global'
						sym = glob.getProperty(name)

					let other = names.get(name)

					if other and other.kind == 'property'
						other.insertText = other.label = "self.{other.label}"

					add(
						label: variable.name
						sortText: '1'
						symbol: sym
					)
			# check for option as well
			let imports = ils.entities.getAutoImportsForFile(self)
			add(...imports)

		# convert to actual completions
		let results = for item in items
			let sym = item.symbol
			let lbl = item.label.name or item.label
			if sym isa Sym
				item.kind ||= sym.semanticKind
				item.label = sym.name
				item.detail = "{sym.semanticKind} {sym.name}"

			if item.sortText == '0'
				# not if it is related to tags?
				if lbl.match(/[A-Z]/)
					item.sortText = '1'

			if filters.kinds.length
				continue unless filters.kinds.indexOf(item.kind) >= 0

			item.kind ||= 'variable'
			if typeof item.kind == 'string'
				item.kind = util.convertCompletionKind(item.kind)

			delete item.symbol	
			item.data ||= {resolved: yes}
			item

		return results


	def getSymbols
		let outline = idoc.getOutline do(item)
			# item.kind = util.convertSymbolKind(item.kind)
			item.range = item.span
			item.selectionRange = item.range
			if typeof item.kind == 'string'
				item.kind = util.convertSymbolKind(item.kind)

		return outline.children

	def onDidChangeTextEditorSelection event
		const now = times.selection = Date.now!
		# console.log 'file selection change',now - times.edited
		if isTyping and (now - times.edited) > 3
			isTyping = no
			$flush('emitFile')
			diagnostics.sync!
		return

export class Imba1File < ImbaFile

export class JSONFile < File

export class AssetFile < File

export class HTMLFile < AssetFile

export class ImageFile < AssetFile

export class SVGFile < AssetFile

	def getCompiledBody
		return 'export default /** @type {ImbaAsset} */({})'
		# super