var content = `<div.one.two title=10 :click.test>`
import {File} from './File'
import {LanguageServer} from './LanguageServer'
import * as util from './utils'
import { parse,TokenizedDocument } from './Parser'
import { FullTextDocument,ImbaTextDocument } from './FullTextDocument'
var imbac = require 'imba/dist/compiler.js'

var tests  = [
	[`<div.one.two title=10 :click.test>`,4]
	[`<div >`,5]
	[`<div :click.stop .test=10>\n`,12,18,23]
	[`<\{name\} title='a'>\n`,7]
	[`<div :test.call(10,200)>\n`,19]
	[`if true\n\tMath.random()\n`,2]
	[`\n<>\n<li> 'test'`,2]
	[`<div> <span> 'test'`,5]
]

if false
	var file = File.new({files: {}, rootFiles: []},'index.imba')

	for test in tests
		file.content = test[0]
		for pos in test.slice(1)
			console.log file.getContextAtLoc(pos)

var conn = {
	sendDiagnostics: do yes
}
var rootFile = '/Users/sindre/repos/vscode-imba/test/main.js'
var ls = LanguageServer.new(conn,null,{
	rootUri: 'file:///Users/sindre/repos/vscode-imba/test'
	rootFiles: []
	debug: true
})
ls.addFile(rootFile)
ls.addFile('completion.js')
# console.log ls.rootFiles
ls.emitRootFiles()

if false
	ls.getSemanticDiagnostics()
	ls.$updateFile('component.imba') do |content| content.replace(/@titl\b/,'@titls')
	ls.getSemanticDiagnostics()
	ls.$updateFile('component.imba') do |content| content.replace(/@titls\b/,'@titl')
	ls.getSemanticDiagnostics()
	ls.inspectProgram()

	ls.getSemanticDiagnostics()
	console.log ls.getSymbols('util.imba')
	
def toffset2ioffset file, start, length
	let iloc = file.originalLocFor(start)
	let range = file.textSpanToRange({ start: start, length: length })
	console.log "orig offset",start,length,iloc,range

def testparse code
	let res = parse(code)
	let pairs = []
	for tok,i in res.tokens
		let next = res.tokens[i + 1]
		let to = next ? next.offset : code.length
		let content = code.slice(tok.offset,to)
		let typ = tok.type.replace('.imba','')
		if typ == 'white' or typ == 'invalid' # or content.match(/[\{\}\[\]\(\)\,]|=/)
			pairs.push(content)
		else
			pairs.push("{content}({typ})")

	# console.log code,res.endState.stack,
	# console.log pairs.join('') + '\n'

if true
	let file = ls.getImbaFile('completion.imba')
	let content = file.getSourceContent()
	let last = 0
	let idx = 0
	while (idx = content.indexOf('# |',last)) > -1
		last = idx + 2
		if let m = content.slice(idx + 3).match(/^\d+/)
			idx = idx - parseInt(m[0])

		console.log 'found index',idx
		console.dir file.getContextAtLoc(idx), {depth: 7}

	# console.log ls.getCompletionsAtPosition('completion.imba',89)
if false
	console.log util.fastParseCode('<div hello=(')
	console.log util.fastParseCode('<div> "')
	console.log util.fastParseCode('<div> "{')
	console.log util.fastParseCode('<div.{')
	console.log util.fastParseCode('<div test=')
	console.log util.fastParseCode('<div v=({')
	console.log util.fastParseCode('<div> <','>')

if true
	testparse('let x,y')
	testparse('let x = 1, y = 2')
	testparse('let x = 1, y = 2')
	testparse('let {x,y} = a')
	testparse('for {x,y},i in test')
	testparse('test(let x = 10, hello)')
	testparse('if let h = 20')
	testparse('if let h = 20\n\tvar test = 10')
	testparse('let {\n\tx,\n\ty\n} = a')
	testparse('let x = /testing/\n')
	testparse('def test a,b\n\tyes')
	testparse('### tester dette ### 10')
	testparse('### css\na\n\n###\n10')
	testparse('<div>')
	testparse('<div.one.two value=10>')
	testparse('<div[item]>')
	testparse('<div title="hello">')
	testparse('<div :test.self.stop>')
	# testparse('def one a,b\n\ttrue')
	# testparse('def one(a,b = z,[x,y])\n\ttrue')
	# testparse('def one(a,b = "one{Math}test",[x,y])\n\ttrue')
	testparse('<div \n\ta=1\n> 10')
	testparse('aba\n### css\na\n\n###\n10')
	if false
		let file = ls.getImbaFile('completion.imba')
		testparse(file.getSourceContent!)
		let t = Date.now!
		let tokens = imbac.tokenize(file.getSourceContent!)
		console.log 'tokenized',Date.now! - t,tokens.length
		testparse(file.getSourceContent!)


if true
	let file = ls.getImbaFile('context.imba')
	let doc = ImbaTextDocument.new('file://test.imba','imba',0,file.getSourceContent!)
	# console.log doc.tokens.getTokens(line: 2)
	# console.log doc.tokens.getTokens(line: 100)
	# console.log doc.tokens.getTokens(line: 103)
	for offset in [25,86,119,155,161,200,229,239,277,300,331,364,365,368]
		let pos = doc.positionAt(offset)
		let ctx = doc.tokens.getContextAtOffset(offset)
		let line = doc.tokens.lineTokens[pos.line]
		let idx = offset - line.offset
		let prev = doc.tokens.lineTokens[pos.line - 1]
		let str = line.lineContent.slice(0,idx) + '|' + line.lineContent.slice(idx)
		console.log ['---',prev.lineContent,str,'---'].join('\n').replace(/\t/g,'  ')
		console.dir ctx, depth: 1


# ls.getCompletionsAtPosition('completion.imba',88)
# console.log ls.getImbaFile('completion.imba').getContextAtLoc(89)
# ls.emitDiagnostics()