module analyzer::sema @if($feature(SEMA));

import analyzer::core;

struct Symbol
{
	Symbol* next;
	Node* node;
	<* `@if(expr)` *>
	Node* condition;
	String qualified_name;
	sz section_id;
}