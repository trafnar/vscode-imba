import {DiagnosticSeverity} from 'vscode-languageserver-types'
import * as config from './Config'

export const DiagnosticSource = {
	Compiler: 1
	TypeScript: 2
	Monarch: 3
}

export const DiagnosticKind = {
	Compiler: 1 << 0
	TypeScript: 1 << 2
	Monarch: 1 << 3
	Semantic: 1 << 4
	Syntactic: 1 << 5
}

const WARN = DiagnosticSeverity.Warning
const ERR = DiagnosticSeverity.Error
const INFO = DiagnosticSeverity.Information

export const ImbaSeverityToLSP = {
	error: ERR
	warning: WARN
	info: INFO
}

# https://github.com/microsoft/TypeScript/blob/master/src/compiler/diagnosticMessages.json
# message: /Type '-?[\d\.]+' is not assignable to type 'string'/
# ideally only for a

const SuppressDiagnostics = [
	
	code: 2322	
	text: /^\$\d+/
	---
	code: 2322 # should only be for dom nodes?
	message: /^Type '(boolean|string|number|ImbaAsset|typeof import\("data:text\/asset;\*"\))' is not assignable to type '(string|number|boolean)'/
	---
	code: 2339
	message: /on type 'EventTarget'/
	---
	code: 2339
	message: /\$CARET\$/
	---
	code: 2339
	message: /Property '_\$SYM\$/
	---
	code: 2339 # option allow array properties
	message: /on type '(.*)\[\]'/
	---
	code: 2339 # option allow array properties
	message: /on type 'Window'/
	---
	code: 2339 # option allow array properties
	message: /on type 'Window & typeof globalThis'/
	---
	code: 2556
	text: /\.\.\.arguments/
	---
	code: 2540 # should be toggled with option
	message: /^Cannot assign to /
	---
	code: 2557
	text: /\.\.\.arguments/
	---
	code: 2554
	test: do({message})
		return no unless typeof message == 'string'
		let m = message.match(/Expected (\d+) arguments, but got (\d+)/)
		return yes if m and parseInt(m[2]) > parseInt(m[1])
		return no
	---
	code: 2339 # should we always?
	message: /on type '\{\}'/
	---
	code: 2304 # dynamic asset items
	message: /Svg[A-Z]/
	---
	code: 2538 # dynamic asset items
	message: /unique symbol' cannot be used as an index type/
]



export class Diagnostic

	static def fromCompiler kind, entry, doc
		if entry.#diagnostic
			return entry.#diagnostic
		
		let rich = new Diagnostic(entry)
		entry.#diagnostic = rich
		return rich

	static def fromTypeScript kind, entry, doc, options = {}
		if entry.#diagnostic !== undefined
			return entry.#diagnostic
		entry.#diagnostic = null
		let file = entry.file
		let compilation = file.getCompilation!
		

		let msg = entry.messageText
		msg = msg.messageText or msg or ''
		let sev = [WARN,ERR,INFO,INFO][entry.category]
		let rawCode = file.text.substr(entry.start,entry.length)
		let rawExpandedCode = file.text.substr(entry.start - 10,entry.length + 10)
	
		# console.log 'from typescript',kind,entry.msg,file.path

		for rule in SuppressDiagnostics
			if rule.code == entry.code
				if rule.text isa RegExp
					return if rule.text.test(rawCode)
				if rule.message isa RegExp
					return if rule.message.test(msg)
				if rule.test isa Function
					return if rule.test({message: msg, text: rawCode})

		if options.suppress
			for rule in options.suppress
				return if rule.test(msg)
		
		let range = compilation.o2iRange(entry.start,entry.start + entry.length)

		if msg.match('does not exist on type')
			sev = WARN

		if !range or Number.isNaN(range.start.character)
			return null

		let diagnostic = new Diagnostic({
			severity: sev
			message: msg.messageText or msg
			range: range
			data: {
				kind: kind
				range: range
				version: compilation.iversion
			}
		},compilation)
		diagnostic.#entry = entry
		entry.#diagnostic = diagnostic

		return diagnostic

	def constructor {severity,message,range,data},compilation
		self.severity = severity
		self.message = message
		self.range = range
		self.data = data or {}
		self.data.range = range
		#cache = {}
		#compilation = compilation
		
	get #range
		#compilation
		
	get #doc
		#compilation..doc
	
	get #file
		#compilation.file
		
	get initialRange
		data.range
		
	get newRange
		#cache.range ||= #compilation.i2d(data.range)
		
	get oldText
		#oldText ||= initialRange.getText(#compilation.ibody)
		
	get newText
		#cache.text ||= newRange.getText(#doc.content)
		
	def toJSON
		{
			range: newRange
			severity: severity
			message: message
		}
		
	def sync
		if #version =? #doc.version
			#cache = {}
		self
	
	get hidden?
		sync!
		return yes if newText != oldText
		return no

export class FileDiagnostic < Diagnostic
	
	get newText
		''
	
	get oldText
		''
	
	get newRange
		initialRange
		
	def sync
		self
	
	get hidden?
		no
		
export class Diagnostics
	def constructor doc
		self.doc = doc
		self.all = []
		self.dirty = no
		
	def fromTypeScript kind, items
		let options = {suppress: []}
		let customRules = doc.program.imbaConfig..diagnostics..suppressErrorRules
		if customRules isa Array
			for item in customRules
				if typeof item == 'string'
					options.suppress.push(new RegExp(item))
		# #tsDiagnostics = items
		items = items.map do Diagnostic.fromTypeScript(kind,$1,doc,options)
		items = items.filter do $1
		return items
	
	def update kind, items, versions = null
		dirty = yes
		
		# remove the previous diagnostics of the same kind
		
		all = all.filter do $1.data.kind != kind

		if kind & DiagnosticKind.TypeScript
			let options = {suppress: []}
			let customRules = doc.program.imbaConfig..diagnostics..suppressErrorRules
			if customRules isa Array
				for item in customRules
					if typeof item == 'string'
						options.suppress.push(new RegExp(item))
			#tsDiagnostics = items
			items = items.map do Diagnostic.fromTypeScript(kind,$1,doc,options)
			items = items.filter do $1

		for item in items
			item.data ||= {}
			item.data.kind ||= kind
			item.data.version ||= doc.version

		if items.length
			console.log 'updating diagnostics',kind,items,versions
		all = all.concat(items)
		sync!
		self

	def clear kind = 0
		# all = all.filter do $1.data.kind != kind
		all = []
		sync yes

	def log ... params
		if doc.logLevel > 0
			console.log(...params)

	def syncItem item,version
		let range = item.range
		let meta = item.data

		if meta.version != version and range

			let oldRange = item.initialRange
			let newRange = item.newRange
			
			let oldText = item.oldText
			let newText = item.newText

			if !newRange.equals(oldRange)
				console.log 'range has changed!!',oldText,newText
				item.range = newRange
				self.dirty = yes

			if newText != oldText
				console.log 'text content of diagnostic range changed',newText,oldText
				# meta.text = text
				item.remove = yes
				self.dirty = yes

			meta.version = version
			# item.data.version = version

		return item

	def sync force = no
		let version = doc.idoc.version
		for item in all
			syncItem(item,version)

		if dirty or force
			send!
		self

	def send
		dirty = no
		let send = all.filter do !$1.remove
		log 'sending',all,send
		doc.program.connection.sendDiagnostics(uri: doc.uri, diagnostics: send)
