module storage

import vmarkdown

pub struct FtsTokenEmission {
pub:
	scope FtsScope
	term  string
}

pub fn fts_tokenize_text(raw string) []string {
	mut tokens := []string{}
	mut current := []u8{}
	for ch in raw.bytes() {
		if fts_is_ascii_word_byte(ch) {
			current << ch
			continue
		}
		if current.len > 0 {
			token := current.bytestr().to_lower()
			if token.len > 0 {
				tokens << token
			}
			current = []u8{}
		}
	}
	if current.len > 0 {
		token := current.bytestr().to_lower()
		if token.len > 0 {
			tokens << token
		}
	}
	return tokens
}

fn fts_is_ascii_word_byte(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
}

pub fn emit_markdown_fts_tokens(raw string) ![]FtsTokenEmission {
	doc := vmarkdown.parse(raw)!
	return emit_markdown_fts_tokens_from_doc(doc)
}

pub fn emit_markdown_fts_tokens_from_doc(doc vmarkdown.Document) []FtsTokenEmission {
	mut out := []FtsTokenEmission{}
	collect_markdown_fts_tokens(doc.children, mut out)
	return out
}

fn collect_markdown_fts_tokens(nodes []vmarkdown.BlockNode, mut out []FtsTokenEmission) {
	for node in nodes {
		match node {
			vmarkdown.MetaNode {}
			vmarkdown.HorizontalRuleNode {}
			vmarkdown.HeadingNode {
				fts_append_tokens(mut out, .heading, markdown_inline_text_value(node.children))
			}
			vmarkdown.ParagraphNode {
				fts_append_tokens(mut out, .paragraph, markdown_inline_text_value(node.children))
			}
			vmarkdown.CodeBlockNode {
				fts_append_tokens(mut out, .code_block, node.content)
			}
			vmarkdown.BlockquoteNode {
				collect_markdown_fts_tokens(node.children, mut out)
			}
			vmarkdown.ListNode {
				for item in node.items {
					fts_append_tokens(mut out, .list_item, markdown_blocks_text(item.children))
					collect_markdown_fts_tokens(item.children, mut out)
				}
			}
		}
	}
}

fn markdown_blocks_text(nodes []vmarkdown.BlockNode) string {
	mut parts := []string{}
	for node in nodes {
		text := markdown_block_text(node)
		if text.len > 0 {
			parts << text
		}
	}
	return parts.join(' ').trim_space()
}

fn markdown_block_text(node vmarkdown.BlockNode) string {
	return match node {
		vmarkdown.MetaNode { '' }
		vmarkdown.HorizontalRuleNode { '' }
		vmarkdown.HeadingNode { markdown_inline_text_value(node.children) }
		vmarkdown.ParagraphNode { markdown_inline_text_value(node.children) }
		vmarkdown.CodeBlockNode { node.content.trim_space() }
		vmarkdown.BlockquoteNode { markdown_blocks_text(node.children) }
		vmarkdown.ListNode {
			mut texts := []string{}
			for item in node.items {
				text := markdown_blocks_text(item.children)
				if text.len > 0 {
					texts << text
				}
			}
			texts.join(' ').trim_space()
		}
	}
}

fn fts_append_tokens(mut out []FtsTokenEmission, scope FtsScope, raw string) {
	for token in fts_tokenize_text(raw) {
		out << FtsTokenEmission{
			scope: scope
			term: token
		}
	}
}
