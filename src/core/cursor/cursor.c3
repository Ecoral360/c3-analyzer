<*
 Cursor is basically a pointer to a specific node
	with the ability to walk and get out data from it.

	represents some Node in the abstract syntax tree for a module
*>
module analyzer::cursor;
import analyzer::core;
import analyzer::sema;

import std::collections::list;

import std::io;

faultdef
	INVALID_NODE,
	UNEXPECTED_KIND,
	NOT_FOUND
;

<*
 Get the spelling/text for the current node.

 Three groups are handled:
 - named declarations, which answer with their own identifier,
 - expressions that carry or point at a name,
 - wrappers such as groups, casts and splats, which are transparent and
   answer with the spelling of what they wrap.

 Anything without a name, statements included, answers with the empty
 string rather than an error, so callers can use the result directly.
*>
fn String? spelling(Node* node, Allocator allocator) => @pool()
{
	if (!node) return "";

	switch (node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = node.as(StructDecl);
			if (!s.name) return "";
			return s.name.text;
		case ENUM_DECL:
			EnumDecl* e = node.as(EnumDecl);
			if (!e.name) return "";
			return e.name.text;
		case VAR_DECL:
			VarDecl* v = node.as(VarDecl);
			if (!v.name) return "";
			return v.name.text;
		case FN_DECL:
			FnDecl* func = node.as(FnDecl);
			if (!func.name) return "";
			return func.name.text;
		case MACRO_DECL:
			MacroDecl* mac = node.as(MacroDecl);
			if (!mac.name) return "";
			return mac.name.text;
		case TYPEDEF_DECL:
			TypedefDecl* td = node.as(TypedefDecl);
			if (!td.name) return "";
			return td.name.text;
		case ALIAS_DECL:
			AliasDecl* ad = node.as(AliasDecl);
			if (!ad.name) return "";
			return ad.name.text;
		case INTERFACE_DECL:
			InterfaceDecl* id = node.as(InterfaceDecl);
			if (!id.name) return "";
			return id.name.text;
		case FAULT_DECL:
			FaultDecl* fault_decl = node.as(FaultDecl);
			if (!fault_decl.name) return "";
			return fault_decl.name.text;
		case ATTRDEF_DECL:
			AttrdefDecl* attr_def = node.as(AttrdefDecl);
			if (!attr_def.name) return "";
			return attr_def.name.text;
		case ATTRIBUTE_DECL:
			AttributeDecl* attr = node.as(AttributeDecl);
			if (!attr.name) return "";
			return attr.name.text;
		case MODULE_DECL:
			ModuleDecl* mod_decl = node.as(ModuleDecl);
			return spelling(mod_decl.path, allocator);
		case IMPORT_DECL:
			// An import can name several modules at once; the first one is
			// what the declaration is taken to spell.
			ImportDecl* imp = node.as(ImportDecl);
			if (!imp.paths.len) return "";
			return spelling(imp.paths[0], allocator);
		case CONTRACT_PARAM:
			ContractParam* contract_param = node.as(ContractParam);
			if (!contract_param.ident) return "";
			return contract_param.ident.text;
		case TYPE_EXPR:
			TypeExpr* type_data = node.as(TypeExpr);
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
			IdentExpr* ident = node.as(IdentExpr);
			if (!ident.ident) return "";
			return ident.ident.text;
		case PATH_EXPR:
			PathExpr* path_expr = node.as(PathExpr);
			if (!path_expr.path) return "";
			return path_expr.path.text;
		case NAMED_ARG_EXPR:
			NamedArgExpr* named = node.as(NamedArgExpr);
			if (!named.name) return "";
			return named.name.text;
		case BUILTIN_EXPR:
			BuiltinExpr* builtin_expr = node.as(BuiltinExpr);
			if (!builtin_expr.name) return "";
			return builtin_expr.name.text;
		case COMPILER_CONST_EXPR:
			// CompilerConstExpr inlines BuiltinExpr, but `as` checks the exact
			// kind, so the two cannot share a cast.
			CompilerConstExpr* const_expr = node.as(CompilerConstExpr);
			if (!const_expr.name) return "";
			return const_expr.name.text;
		case LITERAL_EXPR:
			return literal_spelling(node.as(LiteralExpr), allocator);
		case CALL_EXPR:
			CallExpr* call = node.as(CallExpr);
			return spelling(call.callee, allocator);
		case ACCESS_EXPR:
			// 'x.field' and 'Type::member' both spell as the member.
			AccessExpr* access_expr = node.as(AccessExpr);
			return spelling(access_expr.member, allocator);
		case DESIGNATOR_EXPR:
			DesignatorExpr* designator = node.as(DesignatorExpr);
			if (designator.designator_kind != PERIOD) return "";
			return spelling(designator.data.field, allocator);
		case DESIGNATED_INITIALIZER_EXPR:
			DesignatedInitializerExpr* designated = node.as(DesignatedInitializerExpr);
			return spelling(designated.path, allocator);
		case CAST_EXPR:
			// 'inner' is the target type, 'operand' is the value being cast,
			// and the value is what the expression is named after.
			CastExpr* cast_expr = node.as(CastExpr);
			return spelling(cast_expr.operand, allocator);
		case GROUP_EXPR:
			GroupExpr* group_expr = node.as(GroupExpr);
			return spelling(group_expr.inner, allocator);
		case OPTIONAL_EXPR:
			OptionalExpr* optional_expr = node.as(OptionalExpr);
			return spelling(optional_expr.inner_expr, allocator);
		case MAYBE_DEREF_EXPR:
			MaybeDerefExpr* deref_expr = node.as(MaybeDerefExpr);
			return spelling(deref_expr.left, allocator);
		case SPLAT_EXPR:
			SplatExpr* splat_expr = node.as(SplatExpr);
			return spelling(splat_expr.inner, allocator);
		default:
			return "";
	}
}

<*
 Text of a literal, as it would be written in source.

 Byte literals are left empty: they have no readable spelling.
*>
fn String literal_spelling(LiteralExpr* literal, Allocator allocator) @local
{
	switch (literal.literal_kind)
	{
		case INT_LITERAL:
			return string::format(allocator, "%d", literal.integer);
		case REAL_LITERAL:
			return string::format(allocator, "%f", literal.real);
		case BOOL_LITERAL:
			return literal.boolean ? "true" : "false";
		case NULL_LITERAL:
			return "null";
		case STRING_LITERAL:
			return literal.string;
		case BYTES_LITERAL:
			return "";
	}
}

<*
 Checks if cursor has a specific attribute
*>
fn bool has_attribute(Node* node, AttributeKind kind, Node** out_attribute)
{
	NodeArray temp;
	switch (node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = node.as(StructDecl);
			temp = s.attributes;
			break;
		case INTERFACE_DECL:
			InterfaceDecl* inter = node.as(InterfaceDecl);
			temp = inter.attributes;
			break;
		case FN_DECL:
			FnDecl* func = node.as(FnDecl);
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

fn List{Node*} get_node_path(Node* node, Range range, SourceFile* sf)
{
	List{Node*} node_path; node_path.tinit();
	get_node_path_impl(node, range, sf, &node_path);
	return node_path;
}

macro void get_node_path_from_nodes(SourceFile* sf, Range range, List{Node*}* node_path, node_val) @local
{
	$foreach $member : $Typeof(node_val)::members:
		$switch $member.type:
			$case NodeArray:
				foreach (node : node_val.$member)
				{
					if (get_node_path_impl(node, range, sf, node_path)) break;
				}

			$case Node*:
				get_node_path_impl(node_val.$member, range, sf, node_path);
		$endswitch
	$endforeach
}

fn bool get_node_path_impl(Node* node, Range range, SourceFile* sf, List{Node*}* node_path) @local
{
	if (node == null) return false;

	if (!range.contains_range(node.range)) return false;

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
fn String? raw_type_identifier(Node* node)
{
	if (!node.is_valid() || node.kind != TYPE_EXPR) return NOT_FOUND~;

	Node* current = node;

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
	Range target;
	Node* best_match;
	int best_span;
}

fn ChildVisitResult find_at_callback(Node* cursor, Node* parent, void* user_data)
{
	if (!cursor.is_valid()) return CONTINUE;

	FindAtContext* ctx = (FindAtContext*)user_data;
	Node* node = cursor;

	if (node.range.contains_range(ctx.target))
	{
		int current_span = (node.range.end.line - node.range.start.line) * 1000 +
							(node.range.end.column - node.range.start.column);

		if (ctx.best_match == null || current_span <= ctx.best_span)
		{
			ctx.best_match = cursor;
			ctx.best_span = current_span;
		}

		return RECURSE;
	}

	return CONTINUE;
}

fn Node* find_at(Node*[] slice, Range range)
{
	FindAtContext ctx = {
		.target = range,
		.best_match = {},
		.best_span = 99999999 // Start with a massive fallback span
	};

	foreach (node : slice)
	{
		Node* root_cursor = node;

		if (!visit(root_cursor, {}, { .on_enter = &find_at_callback }, &ctx))
		{
			break;
		}
	}

	return ctx.best_match;
}

/*
<*
 Get the raw source code fragment corresponding exactly to this node.
 @param [&in] sf : "Which file to acquire the source from"
*>
fn String? Cursor.source_text(&node, SourceFile* sf)
{
	if (!node.is_valid()) return NOT_FOUND~;

	String full_source = sf.source;



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
fn String? Cursor.signature_text(&node, SourceFile* sf)
{
	String text = node.source_text(sf)!;

	switch (node.kind)
	{
		case FN_DECL:
			FnDecl* fn_decl = node.as(FnDecl);
			if (fn_decl.body)
			{
				return sf.source[node.offset.start..fn_decl.body.offset.start - 1]
					.trim()
					.strip_suffix("{")
					.strip_suffix("=>")
					.trim();
			}
			else
			{
				return sf.source[node.offset.start..node.offset.end - 1].trim();
			}


		case MACRO_DECL:
			MacroDecl* mac_decl = node.as(MacroDecl);
			return sf.source[node.offset.start..mac_decl.body.offset.start - 1]
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

*/

fn Node*? contract(Node* node)
{
	switch (node.kind)
	{
		case FN_DECL:
		{
			FnDecl* decl = node.as(FnDecl);
			if (try val = decl.contract.get())
			{
				return val;
			}
		}
		case MACRO_DECL:
		{
			MacroDecl* decl = node.as(MacroDecl);
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
fn String? docs(Node* node)
{
	if (!node) return "";

	if (try val = contract(node) && val)
	{
		return val.as(ContractDecl).comment.text;
	}

	return "";
}

fn Node* find_member_in_type(Node* node, String name)
{
	switch (node.kind)
	{
		case STRUCT_DECL:
		{
			StructDecl* decl = node.as(StructDecl);
			foreach (field : decl.fields)
			{
				String field_name = cursor::spelling(field, tmem) ?? "";
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

fn Node* get_type(Node* node)
{
	switch (node.kind)
	{
		case STRUCT_DECL:
			StructDecl* decl = node.as(StructDecl);
			return decl.type;
		case FN_DECL:
			FnDecl* decl = node.as(FnDecl);
			return decl.associated_type == null ? decl.ret_type : decl.associated_type;
		case ENUM_DECL:
			EnumDecl* decl = node.as(EnumDecl);
			return decl.backing_type;
		case VAR_DECL:
			VarDecl* decl = node.as(VarDecl);
			return decl.type;
		default:
			return null;
	}
}
