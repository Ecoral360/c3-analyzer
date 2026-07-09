<*
 Cursor is basically a pointer to a specific node
	with the ability to walk and get out data from it.

	represents some Node in the abstract syntax tree for a module
*>
module analyzer::cursor;

import analyzer::workspace;
import analyzer::core;
import analyzer::sema;

import std::collections::list;

import std::io;

faultdef
	INVALID_NODE,
	UNEXPECTED_KIND,
	NOT_FOUND
;

struct Cursor
{
	Node* node;
}

fn bool Cursor.is_valid(self) @inline
{
	return self.node != null;
}

<*
 Get the spelling/text for the current node
 @require self.node != null
*>
fn String? Cursor.spelling(&self, Allocator allocator) => @pool()
{
	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(StructDecl);
			if (!s.name) return "";
			return s.name.text;
		case VAR_DECL:
			VarDecl* v = self.node.as(VarDecl);
			if (!v.name) return "";
			return v.name.text;
		case FN_DECL:
			FnDecl* func = self.node.as(FnDecl);
			if (!func.name) return "";
			return func.name.text;
		case MACRO_DECL:
			MacroDecl* mac = self.node.as(MacroDecl);
			if (!mac.name) return "";
			return mac.name.text;
		case TYPEDEF_DECL:
			TypedefDecl* td = self.node.as(TypedefDecl);
			if (!td.name) return "";
			return td.name.text;
		case ALIAS_DECL:
			AliasDecl* ad = self.node.as(AliasDecl);
			if (!ad.name) return "";
			return ad.name.text;
		case INTERFACE_DECL:
			InterfaceDecl* id = self.node.as(InterfaceDecl);
			if (!id.name) return "";
			return id.name.text;
		case TYPE_EXPR:
			TypeExpr* type_data = self.node.as(TypeExpr);
			if (type_data.type_kind == TYPE_IDENTIFIER)
			{
				if (!type_data.unresolved.name) return "";
				String type_name = type_data.unresolved.name.text;
				if (type_data.unresolved.path != null)
				{
					PathExpr* prefix_path = type_data.unresolved.path.as(PathExpr);
					String prefix_str     = prefix_path.path.text;
					return prefix_str.tconcat(type_name).copy(allocator);
				}
				return type_name;
			}
			return "";
		case IDENT_EXPR:
			IdentExpr* ident = self.node.as(IdentExpr);
			if (!ident.ident) return "";
			return ident.ident.text;
		default:
			return "";
	}
}

<*
 Checks if cursor has a specific attribute
*>
fn bool Cursor.has_attribute(&self, AttributeKind kind, Node** out_attribute)
{
	NodeArray temp;
	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(StructDecl);
			temp = s.attributes;
			break;
		case INTERFACE_DECL:
			InterfaceDecl* inter = self.node.as(InterfaceDecl);
			temp = inter.attributes;
			break;
		case FN_DECL:
			FnDecl* func = self.node.as(FnDecl);
			temp = func.attributes;
			break;
		default:
			return false;
	}
	
	foreach (attr : temp)
	{
		AttributeDecl* attr_decl = attr.as(AttributeDecl);
		if (attr_decl.attribute_kind == kind)
		{
			if (out_attribute)
			{
				*out_attribute = attr;
			}

			return true;
		}
	}

	return false;
}

<*
 use a binary-search to find wether any error node has
 the byte offset / byte range of this cursor
 Note: has not yet been tested
 @param [&in] section
*>
fn bool Cursor.has_error(&self, ModuleSection* section)
{
	NodeArray errors = section.source_file.ast.error_nodes.array_view();
	sz len           = errors.len;
	if (len == 0) return false;

	sz node_start = self.node.offset.start;
	sz node_end   = self.node.offset.end;

	sz low  = 0;
	sz high = len - 1;

	while (low <= high)
	{
		sz mid    = low + (high - low) / 2;
		Node* err = errors[mid];

		if (node_start <= err.offset.start && err.offset.end <= node_end)
		{
			return true;
		}

		if (err.offset.start > node_end)
		{
			high = mid - 1;
		}
		else
		{
			low = mid + 1;
		}
	}

	return false;
}

<*

*>
fn Node* find_node_from_offset(Node* node, int offset)
{
	if (node == null) return null;

	if (offset < node.offset.start || offset > node.offset.end)
	{
		return null;
	}

	plog::debug("Found node: (%s) - (%s) %s:%s", node.kind, offset, node.offset.start, node.offset.end);

	return node;
}

macro Node* find_innermost_from_nodes(SourceFile* sf, int offset, ...) @local 
{
	Node* result;
	$for int $i = 0; $i < $vaarg.len; $i++:
		$if $Typeof($vaarg[$i]) == NodeArray:
			foreach (node : $vaarg[$i])
			{
				result = find_innermost_node(node, offset, sf);
				if (result) return result;
			}
		$else
			result = find_innermost_node($vaarg[$i], offset, sf);
			if (result) return result;
		$endif
	$endfor
	return null;
}

fn List{Node*} get_node_path(Node* node, int offset, SourceFile* sf)
{
	List{Node*} node_path; node_path.tinit();
	get_node_path_impl(node, offset, sf, &node_path);
	return node_path;
}

macro void get_node_path_from_nodes(SourceFile* sf, int offset, List{Node*}* node_path, node_val) @local 
{
	$foreach $member : $Typeof(node_val)::members:
		$switch $member.type:
			$case NodeArray:
				foreach (node : node_val.$member)
				{
					if (get_node_path_impl(node, offset, sf, node_path)) break;
				}

			$case Node*:
				get_node_path_impl(node_val.$member, offset, sf, node_path);
		$endswitch
	$endforeach
}

fn bool get_node_path_impl(Node* node, int offset, SourceFile* sf, List{Node*}* node_path) @local
{
	if (node == null) return false;

	if (offset < node.offset.start || offset > node.offset.end) return false;

	node_path.push(node);

	var $impl_switch = "switch (node.kind) {";

	//$foreach $node_kind : NodeKind::values :
	//	$if $node_kind != MISSING &&& $node_kind != NOP_STMT:
	//		$impl_switch +++= @sprintf("case %s: ", $node_kind.description);
	//		$impl_switch +++= @sprintf("var %s @safeinfer = node.as(%s);", @str_lower($node_kind.description), $node_kind.description);
	//		$impl_switch +++= @sprintf("get_node_path_from_nodes(sf, offset, node_path, *%s);", @str_lower($node_kind.description));
	//	$endif
//
	//$endforeach

	$impl_switch +++= "default: }";
	$expand($impl_switch);

	return true;
}

<*
 Extracts the raw, un-prefixed identifier string from a TYPE_EXPR node.
 Example: 'List*' -> 'List'
*>
fn String? Cursor.raw_type_identifier(&self)
{
	if (!self.is_valid() || self.node.kind != TYPE_EXPR) return NOT_FOUND~;

	Node* current = self.node;

	while (current && current.kind == TYPE_EXPR)
	{
		TypeExpr* data = current.as(TypeExpr);

		switch (data.type_kind)
		{
			case TYPE_IDENTIFIER:
			{
				if (!data.unresolved.name) return "";
				return data.unresolved.name.text;
			}
			case TYPE_POINTER:
			case TYPE_SLICE:
				current = data.modify.base;
				break;
			case TYPE_ARRAY:
			case TYPE_VECTOR:
				current = data.array.base;
				break;
			case TYPE_GENERIC:
				current = data.generic.base;
				break;
			default:
		}
	}

	return NOT_FOUND~;
}

struct FindAtContext
{
	int target_offset;
	Cursor best_match;
	sz best_span;
}

fn ChildVisitResult find_at_callback(Cursor cursor, Cursor parent, void* user_data)
{
	if (!cursor.is_valid()) return CONTINUE;

	FindAtContext* ctx = (FindAtContext*)user_data;
	Node* node = cursor.node;

	if (ctx.target_offset >= (int)node.offset.start && ctx.target_offset <= (int)node.offset.end)
	{
		sz current_span = (sz)node.offset.end - node.offset.start;

		if (ctx.best_match.node == null || current_span <= ctx.best_span)
		{
			ctx.best_match = cursor;
			ctx.best_span = current_span;
		}

		return RECURSE;
	}

	return CONTINUE;
}

fn Cursor find_at(ModuleSection* sec, int offset)
{
	SourceFile* sf = sec.source_file;
	if (sf.ast == null || sf.ast.top_level_nodes.len() == 0)
	{
		return {};
	}

	FindAtContext ctx = {
		.target_offset = offset,
		.best_match = {},
		.best_span = 99999999 // Start with a massive fallback span
	};

	foreach (root_node : sf.ast.top_level_nodes)
	{
		Cursor root_cursor = { .node = root_node };
		
		if (!visit(root_cursor, {}, { .on_enter = &find_at_callback }, &ctx)) 
		{
			break;
		}
	}
	
	return ctx.best_match;
}

<*
 Get the raw source code fragment corresponding exactly to this node.
 @param [&in] sf : "Which file to acquire the source from"
*>
fn String? Cursor.source_text(&self, SourceFile* sf)
{
	if (!self.is_valid()) return NOT_FOUND~;

	String full_source = sf.source; 

	sz start = (sz)self.node.offset.start;
	sz end   = (sz)self.node.offset.end;

	if (start > full_source.len || end > full_source.len || start > end)
	{
		return INVALID_NODE~;
	}

	return full_source[start..end];
}

<*
 Extracts just the signature part of a declaration node
 @param [&in] sf
*>
fn String? Cursor.signature_text(&self, SourceFile* sf)
{
	String text = self.source_text(sf)!;

	switch (self.node.kind)
	{
		case FN_DECL:
			FnDecl* fn_decl = self.node.as(FnDecl);
			if (fn_decl.body)
			{
				return sf.source[self.node.offset.start..fn_decl.body.offset.start - 1]
					.trim()
					.strip_suffix("{")
					.strip_suffix("=>")
					.trim();
			}
			else 
			{
				return sf.source[self.node.offset.start..self.node.offset.end - 1].trim();
			}


		case MACRO_DECL:
			MacroDecl* mac_decl = self.node.as(MacroDecl);
			return sf.source[self.node.offset.start..mac_decl.body.offset.start - 1]
				.trim()
				.strip_suffix("{")
				.strip_suffix("=>")
				.trim();

		case ATTRDEF_DECL:
		case ATTRIBUTE_DECL:
		case CONTRACT_DECL:
		case STRUCT_DECL:
		case ENUM_DECL:
		case VAR_DECL:
		case MODULE_DECL:
		case IMPORT_DECL:
		case ALIAS_DECL:
		case TYPEDEF_DECL:
		case FAULT_DECL:
		case FAULTDEF_DECL:
		case GENERIC_DECL:
		case INTERFACE_DECL:
		case CT_EXPAND_DECL:
		case CT_ASSERT_DECL:
			break;

		default:
			return UNEXPECTED_KIND~;
	}


	return text.trim();
}


fn Node*? Cursor.contract(&self)
{
	switch (self.node.kind)
	{
		case FN_DECL:
		{
			FnDecl* decl = self.node.as(FnDecl);
			if (try val = decl.contract.get())
			{
				return val;
			}
		}
		case MACRO_DECL:
		{
			MacroDecl* decl = self.node.as(MacroDecl);
			if (try val = decl.contract.get())
			{
				return val;
			}
		}
		default:
			break;
	}

	return null;
}

<*
*>
fn String? Cursor.docs(&self)
{
	if (!self.node.is_valid()) return "";

	if (try val = self.contract() && val)
	{
		return val.as(ContractDecl).comment.text;
	}

	return "";
}

<*
 @require self.is_valid()
*>
fn Node* Cursor.find_member_in_type(&self, String name)
{
	switch (self.node.kind)
	{
		case STRUCT_DECL:
		{
			StructDecl* decl = self.node.as(StructDecl);
			foreach (field : decl.fields)
			{
				Cursor field_cursor = { field };
				String field_name = field_cursor.spelling(tmem) ?? "";
				if (field_name == name)
				{
					return field;
				}
			}
			return null;
		}
		default:
			return null;
	}
}
