module analyzer::core::ast::serialize @if($feature(ANALYZER_CLI));

import std::collections::nullable;
import std::collections::maybe;
import std::io;

alias JsonOutput @local = DString;

fn void push_indent(JsonOutput* output, int indent, int depth)
{
	if (indent != -1) output.append_char_repeat(' ', (sz) (indent * depth));
}
fn void push_newline(JsonOutput* output, int indent, String or = "")
{
	if (indent != -1) 
	{
		output.append_char('\n');
	}
	else if (lengthof(or) > 0)
	{
		output.append(or);
	}
}

macro void serialize(JsonOutput* output, item, int indent, int depth) @local
{
	$switch:
		$case $defined(Nullable{Node} x = item):
		$case $Typeof(item) == Node*:
			node_serialize((Node*) item, output,  indent, depth);

		$case $Typeof(item)::kind == BITSTRUCT:
			output.start_obj(indent);
			$foreach $m : $Typeof(item)::members:
				$if $Typeof(item.$m) == bool:
					if (item.$m) output.ser_entry($m.name, item.$m,   indent, depth + 1);
				$else
					output.ser_entry($m.name, item.$m, indent, depth + 1);
				$endif
			$endforeach
			output.end_obj(indent, depth);

		$case $Typeof(item) == TypeExpr:
			$if TypeExpr::members.len != 3:
				$error "UPDATE THIS CODE HERE";
			$endif
			output.start_obj(indent);

			output.ser_entry("kind", item.kind,   indent, depth + 1);
			output.ser_entry("optional", item.optional,  indent, depth + 1);
			var $sw = "switch (item.kind.ordinal) {";
			$foreach $i, $m : TypeExpr::members[^1].members:
				$sw +++= @sprintf(`case %s: output.ser_entry("%s", item.$eval("%s"),   indent, depth + 1);`, $i, $m.name, $m.name);
			$endforeach
			$sw +++= "default: }";
			$expand($sw);

			output.end_obj(indent, depth);

		$case $Typeof(item)::kind == STRUCT:
			output.start_obj(indent);
			$foreach $m : $Typeof(item)::members:
				output.ser_entry($m.name, item.$m, indent, depth + 1);
			$endforeach
			output.end_obj(indent, depth);

		$case $Typeof(item) == Location:
			output.appendf("{ line = %s, column = %s }", item.line, item.column);

		$case $defined(item[0]) &&& $defined(lengthof(item)):
			sz l_len = lengthof(item);
      	if (l_len == 0)
			{
				output.append("[]");
				return;
			}
		output.append("[");
		push_newline(output, indent);

      	foreach (i, el : item) {
				push_indent(output, indent, depth + 1);
				$if $Typeof(el) == Node*:
					node_serialize(el, output,   indent, depth);
				$else
					serialize(output, el,   indent, depth + 1);
				$endif
        if (i < l_len - 1) output.append_char(',');
        push_newline(output, indent, or: " ");
      	}
		push_indent(output, indent, depth);
      	output.append("]");

		$case $defined(item.get()) &&& $defined(item.get()!) &&& $defined(Maybe{$Typeof(item.get()!!)} x = item):
			if (try v = item.get())
			{
				serialize(output, v,  indent, depth);
			}
			else
			{
				output.append("null");
			}

		$default:
			output.appendf(`"%s"`, item);

	$endswitch
}

macro void JsonOutput.ser_entry(&self, String key, item, int indent, int depth)
{
	push_indent(self, indent, depth);
	self.appendf("\"%s\": ", key.treplace("\"", "\\\""));
	serialize(self, item,   indent, depth);
	self.append(",");
	push_newline(self, indent, or: " ");
}

fn void JsonOutput.start_obj(&self, int indent)
{
	self.append_char('{');
	push_newline(self, indent);
}
fn void JsonOutput.end_obj(&self, int indent, int depth)
{
	if (self.char_at(self.len() - 2) != ',')
	{
		if (indent != -1) self.chop(self.len() - 1);
		self.append('}');
	}
	else
	{
		self.chop(self.len() - 2);
		push_newline(self, indent, or: " ");
		push_indent(self, indent, depth);
		self.append_char('}');
	}
}

fn void node_serialize(Node* self, JsonOutput* output, int indent, int depth) @local
{
	if (self == null)
	{
		output.append("null");
		return;
	}

	output.start_obj(indent);
	output.ser_entry("id", self.id, indent, depth + 1);
	output.ser_entry("kind", self.kind, indent, depth + 1);
	output.ser_entry("visibility", self.visibility, indent, depth + 1);
	output.ser_entry("flags", self.flags, indent, depth + 1);
	output.ser_entry("range.start", self.range.start, indent, depth + 1);
	output.ser_entry("range.end", self.range.end, indent, depth + 1);

	var $sw = "switch (self.kind) {";
	//$foreach $m : Node::members[^1].members:
	//	$sw +++= @sprintf(`case %s: output.ser_entry("%s", self.$eval("%s"),  indent, depth + 1);`, @str_upper($m.name), $m.name, $m.name);
	//$endforeach
	$sw +++= "default: }";
	$expand($sw);

	output.end_obj(indent, depth);
}

<* 
	@param indent : "if its value is -1, the output won't be prettified (all on one line). Else, it will be the indent size"
*>
fn String Node.serialize(&self, Allocator allocator = tmem, int indent = -1)
{
	JsonOutput output;
	output = output.init(allocator);

	node_serialize(self, &output,  indent, 0);
	return output.str_view();
}
