module memory

import crypto.sha256
import vmarkdown

pub enum MarkdownEmbeddingScope {
	block
	path
}

pub struct MarkdownEmbeddingTarget {
pub:
	id            string
	scope         MarkdownEmbeddingScope
	kind          string
	content_id    string
	occurrence_id string
	parent_id     string
	anchor        string
	order         int
	path_hint     string
	text          string
}

pub interface EmbeddingEngine {
	model_name() string
	dimensions() int
mut:
	embed(text string) ![]f32
	embed_batch(texts []string) ![][]f32
}

struct MarkdownEmbeddingCollector {
	root_id string
mut:
	targets       []MarkdownEmbeddingTarget
	sibling_dupes map[string]int
}

pub fn markdown_embedding_targets(raw string) ![]MarkdownEmbeddingTarget {
	doc := vmarkdown.parse(raw)!
	root_id := doc.stable_id()
	return markdown_embedding_targets_from_doc(root_id, doc)
}

pub fn markdown_embedding_texts(targets []MarkdownEmbeddingTarget) []string {
	mut out := []string{cap: targets.len}
	for target in targets {
		out << target.text
	}
	return out
}

fn markdown_embedding_targets_from_doc(root_id string, doc vmarkdown.Document) []MarkdownEmbeddingTarget {
	mut collector := MarkdownEmbeddingCollector{
		root_id:       root_id
		sibling_dupes: map[string]int{}
	}
	mut anchor_stack := []string{}
	for idx, block in doc.children {
		collector.collect_block(block, root_id, '/', mut anchor_stack, 'blocks[${idx}]',
			idx)
	}
	collector.collect_heading_path_targets(doc.children)
	return collector.targets.clone()
}

fn (mut collector MarkdownEmbeddingCollector) collect_block(block vmarkdown.BlockNode, parent_id string, current_anchor string, mut anchor_stack []string, path string, order int) {
	content_id := block.stable_id()
	dup_key := '${parent_id}|${content_id}'
	dup_ordinal := collector.sibling_dupes[dup_key] or { 0 }
	collector.sibling_dupes[dup_key] = dup_ordinal + 1
	mut anchor := current_anchor
	match block {
		vmarkdown.HeadingNode {
			segment := heading_anchor_segment(block)
			if block.level <= anchor_stack.len {
				anchor_stack = anchor_stack[..block.level - 1].clone()
			}
			anchor_stack << segment
			anchor = '/' + anchor_stack.join('/')
		}
		else {}
	}
	occurrence_id := markdown_hash_id([parent_id, content_id, dup_ordinal.str(), anchor, path])
	kind := markdown_embedding_block_kind(block)
	text := markdown_block_text(block)
	if should_embed_markdown_block(block) && text.len > 0 {
		collector.targets << MarkdownEmbeddingTarget{
			id:            '${collector.root_id}:block:${occurrence_id}'
			scope:         .block
			kind:          kind
			content_id:    content_id
			occurrence_id: occurrence_id
			parent_id:     parent_id
			anchor:        anchor
			order:         order
			path_hint:     path
			text:          text
		}
	}
	match block {
		vmarkdown.BlockquoteNode {
			for idx, child in block.children {
				collector.collect_block(child, occurrence_id, anchor, mut anchor_stack,
					'${path}.children[${idx}]', idx)
			}
		}
		vmarkdown.ListNode {
			for item_idx, item in block.items {
				for child_idx, child in item.children {
					collector.collect_block(child, occurrence_id, anchor, mut anchor_stack,
						'${path}.items[${item_idx}].children[${child_idx}]', child_idx)
				}
			}
		}
		else {}
	}
}

fn (mut collector MarkdownEmbeddingCollector) collect_heading_path_targets(blocks []vmarkdown.BlockNode) {
	for idx, block in blocks {
		heading := match block {
			vmarkdown.HeadingNode { block }
			else { continue }
		}
		mut parts := []string{}
		for next_idx in idx .. blocks.len {
			next := blocks[next_idx]
			match next {
				vmarkdown.HeadingNode {
					if next_idx != idx && next.level <= heading.level {
						break
					}
				}
				else {}
			}
			text := markdown_block_text(next)
			if text.len > 0 {
				parts << text
			}
		}
		text := parts.join('\n\n').trim_space()
		if text.len == 0 {
			continue
		}
		content_id := block.stable_id()
		path := 'blocks[${idx}]'
		anchor := heading_anchor_for_block_index(blocks, idx)
		occurrence_id := markdown_hash_id([collector.root_id, content_id, '0', anchor, path])
		collector.targets << MarkdownEmbeddingTarget{
			id:            '${collector.root_id}:path:${occurrence_id}'
			scope:         .path
			kind:          'heading_path'
			content_id:    content_id
			occurrence_id: occurrence_id
			parent_id:     collector.root_id
			anchor:        anchor
			order:         idx
			path_hint:     path
			text:          text
		}
	}
}

fn heading_anchor_for_block_index(blocks []vmarkdown.BlockNode, target_idx int) string {
	mut anchor_stack := []string{}
	for idx in 0 .. target_idx + 1 {
		block := blocks[idx]
		match block {
			vmarkdown.HeadingNode {
				if block.level <= anchor_stack.len {
					anchor_stack = anchor_stack[..block.level - 1].clone()
				}
				anchor_stack << heading_anchor_segment(block)
			}
			else {}
		}
	}
	if anchor_stack.len == 0 {
		return '/'
	}
	return '/' + anchor_stack.join('/')
}

fn should_embed_markdown_block(block vmarkdown.BlockNode) bool {
	return match block {
		vmarkdown.ParagraphNode { true }
		vmarkdown.CodeBlockNode { true }
		else { false }
	}
}

fn markdown_embedding_block_kind(block vmarkdown.BlockNode) string {
	return match block {
		vmarkdown.HeadingNode { 'heading' }
		vmarkdown.ParagraphNode { 'paragraph' }
		vmarkdown.CodeBlockNode { 'code_block' }
		vmarkdown.HorizontalRuleNode { 'horizontal_rule' }
		vmarkdown.MetaNode { 'meta' }
		vmarkdown.BlockquoteNode { 'blockquote' }
		vmarkdown.ListNode { 'list' }
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
		vmarkdown.MetaNode { markdown_meta_text(node) }
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

fn markdown_meta_text(node vmarkdown.MetaNode) string {
	mut keys := node.data.keys()
	keys.sort()
	mut parts := []string{}
	for key in keys {
		value := node.data[key].trim_space()
		if key.len > 0 {
			parts << key
		}
		if value.len > 0 {
			parts << value
		}
	}
	return parts.join(' ').trim_space()
}

fn heading_anchor_segment(node vmarkdown.HeadingNode) string {
	text := markdown_slug(markdown_inline_text(node.children))
	return 'h${node.level}:${text}'
}

fn markdown_inline_text(nodes []vmarkdown.InlineNode) string {
	mut parts := []string{}
	for node in nodes {
		match node {
			vmarkdown.TextNode { parts << node.text }
			vmarkdown.CodeSpanNode { parts << node.text }
			vmarkdown.EmphasisNode { parts << markdown_inline_text(node.children) }
			vmarkdown.StrongNode { parts << markdown_inline_text(node.children) }
			vmarkdown.LinkNode { parts << markdown_inline_text(node.text) }
			vmarkdown.ImageNode { parts << markdown_inline_text(node.alt) }
		}
	}
	return parts.join(' ').trim_space()
}

fn markdown_inline_text_value(nodes []vmarkdown.InlineNode) string {
	return markdown_inline_text(nodes)
}

fn markdown_slug(text string) string {
	if text.len == 0 {
		return 'empty'
	}
	mut out := []u8{}
	mut last_dash := false
	for b in text.to_lower().bytes() {
		if (b >= `a` && b <= `z`) || (b >= `0` && b <= `9`) {
			out << b
			last_dash = false
			continue
		}
		if !last_dash {
			out << `-`
			last_dash = true
		}
	}
	mut slug := out.bytestr().trim('-')
	if slug.len == 0 {
		slug = 'empty'
	}
	if slug.len > 48 {
		slug = slug[..48]
	}
	return slug
}

fn markdown_hash_id(parts []string) string {
	return sha256.sum(parts.join('|').bytes()).hex()[..16]
}
