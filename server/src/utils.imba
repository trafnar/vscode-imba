import {CompletionItemKind} from 'vscode-languageserver-types'
import {URI} from 'vscode-uri'

export def uriToPath uri
	URI.parse(uri).path

export def rangeFromTextSpan span
	@rangeFromTextSpan(span.start,span.end)
	
export def rangeFromLocations start, end
	return
		start:
			line: Math.max(0, start.line - 1),
			character: Math.max(start.offset - 1, 0)
		end:
			line: Math.max(0, end.line - 1)
			character: Math.max(0, end.offset - 1)

const COMPLETION_KIND_MAP = {
	property: CompletionItemKind.Field
	method: CompletionItemKind.Method
	text: CompletionItemKind.Text
	operator: CompletionItemKind.Operator
	class: CompletionItemKind.Class
	var: CompletionItemKind.Variable
	function: CompletionItemKind.Function
	const: CompletionItemKind.Constant
	module: CompletionItemKind.Module
	keyword: CompletionItemKind.Keyword
	alias: CompletionItemKind.Variable
}

export def convertCompletionKind kind, entry
	console.log 'kind',kind,entry.name
	return COMPLETION_KIND_MAP[kind] or CompletionItemKind.Method