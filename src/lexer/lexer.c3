module analyzer::lexer;

module analyzer::core::lexer;

import std::io;
import analyzer::lexer;

import std::collections::list;

<*
 @param [&in] ctx : "main context"
 @require ctx.current_source_file != null
*>
fn Lexer* create(AnalyzerContext* ctx)
{
	Lexer* lexer = alloc::new(ctx.allocator, Lexer);

	lexer.ctx = ctx;
	lexer.tokens.init(ctx.allocator);
	lexer.buffer = ctx.current_source_file.content;

	return lexer;
}

fn void free(AnalyzerContext* ctx, Lexer* lexer)
{
	lexer.tokens.free();
	alloc::free(ctx.allocator, lexer);
}

struct Token
{
	TokenKind kind;
	String value;
	Range range;
}

struct Lexer
{
	AnalyzerContext* ctx;
	String buffer;
	List{Token} tokens;
	Location location;
	char current;
	int index;
}

fn bool Token.is_eof(&self) @inline => self.kind == EOF;

fn bool is_digit(char c) @inline => c.is_digit();
fn bool is_alpha(char c) @inline => c.is_alpha();
fn bool is_ident(char c) @inline => is_alpha(c) || is_digit(c) || c == '_';
fn bool is_hex(char c) @inline => ascii::is_xdigit(c);

fn bool is_all_upper(String text)
{
	bool has_alpha = false;
	if (text == "_") return false;

	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c >= 'a' && c <= 'z') return false;
		if ((c >= 'A' && c <= 'Z') || c == '_') has_alpha = true;
	}
	return has_alpha; // Ensure "123_" isn't counted as CONST_IDENT
}

fn char Lexer.peek(&self, sz ahead = 1) @inline
{
	if (self.index + ahead >= self.buffer.len) return 0;
	return self.buffer[self.index + ahead];
}

fn String Lexer.get_string(&self, int start, int len)
{
	return self.buffer[start:len];
}

fn void skip_whitespace(Lexer* self)
{
	while (self.current != 0 && self.current.is_space())
	{
		advance(self);
	}
}

fn Token lex_line_comment(Lexer* self, int start_pos)
{
	Location start = self.location;
	int start_index = self.index;
	advance(self, 2);
	while (self.current != 0)
	{
		if (self.peek() == '\n') break;
		advance(self);
	}

	return {
		.kind = LINE_COMMENT,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token lex_block_comment(Lexer* self, int start_pos)
{
	Location start = self.location;
	int start_index = self.index;
	self.advance(2); // Skip the initial '/*'
	int depth = 1;
	while (!self.current != 0 && depth != 0)
	{
		if (self.current == '/' && self.peek(1) == '*')
		{
			self.advance(2);
			depth++;
		}
		else if (self.current == '*' && self.peek(1) == '/')
		{
			self.advance(2);
			depth--;
		}
		else
		{
			advance(self);
		}
	}

	if (depth > 0)
	{
		return {
			.kind = ERROR,
			.value = self.get_string(stat, self.index - start_index),
			.range = {
				.start = start,
				.end = self.location
			}
		};
	}

	return { 
		.kind = BLOCK_COMMENT,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token? lex_char(Lexer* self, int start)
{
	Location start = self.location;
	int start_index = self.index;
	advance(self);

	while (self.current != 0)
	{
		char c = self.buffer[self.index];

		if (c == '\'')
		{
			advance(self);
			return { 
				.kind = CHAR_LITERAL,
				.value = self.get_string(stat, self.index - start_index),
				.range = {
					.start = start,
					.end = self.location
				}
			};
		}

		if (c == '\\')
		{
			char next = self.peek();
			if (next == 'x')
			{
			   	self.advance(4);
			} 
			else 
			{
				self.advance(2);
			}
			continue;
		}

		advance(self);
	}

	return {
		.kind = ERROR,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token? lex_string(Lexer* self)
{
	Location start = self.location;
	int start_index = self.index;
	advance(self);

	while (self.current != 0)
	{
		char c = self.current;

		if (c == '"')
		{
			advance(self);
			return { 
				.kind = STRING_LITERAL,
				.value = self.get_string(stat, self.index - start_index),
				.range = {
					.start = start,
					.end = self.location
				}
			};
		}

		if (c == '\\')
		{
			advance(self, 2);
			continue;
		}

		advance(self);
	}

	return {
		.kind = STRING_LITERAL,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token lex_raw_string(Lexer* self)
{
	Location start = self.location;
	int start_index = self.index;
	advance(self); // Skip the opening `

	while (self.current != 0)
	{
		if (self.current == '`')
		{
			if (self.peek() == '`')
			{
				advance(self, 2);
				continue;
			}
			else
			{
				advance(self);
				return {
					.kind = STRING_LITERAL,
					.value = self.get_string(start_index, self.index - start_index),
					.range = {
						.start = start,
						.end = self.location
					}
				};
			}
		}
		advance(self);
	}

	return {
		.kind = ERROR,
		.value = self.get_string(start_index, self.index - start_index),
		.range = {
			.start = start,
			.end = self.range
		}
	};
}

fn TokenKind lookup_keyword(String text)
{
	switch (text)
	{
		// Top-Level Explicit Keywords
		case "alias": return ALIAS;
		case "attrdef": return ATTRDEF;
		case "bitstruct": return BITSTRUCT;
		case "const": return CONST;
		case "constdef": return CONSTDEF;
		case "enum": return ENUM;
		case "faultdef": return FAULTDEF;
		case "fn": return FN;
		case "import": return IMPORT;
		case "interface": return INTERFACE;
		case "macro": return MACRO;
		case "module": return MODULE;
		case "typedef": return TYPEDEF;
		case "struct": return STRUCT;
		case "union": return UNION;
		// Explicit Keywords
		case "any": return ANY_TYPE;
		case "asm": return ASM;
		case "assert": return ASSERT;
		case "break": return BREAK;
		case "case": return CASE;
		case "catch": return CATCH;
		case "continue": return CONTINUE;
		case "default": return DEFAULT;
		case "defer": return DEFER;
		case "do": return DO;
		case "else": return ELSE;
		case "false": return FALSE;
		case "for": return FOR;
		case "foreach": return FOREACH;
		case "foreach_r": return FOREACH_R;
		case "if": return IF;
		case "lengthof": return LENGTHOF;
		case "nextcase": return NEXTCASE;
		case "null": return NULL;
		case "return": return RETURN;
		case "static": return STATIC;
		case "switch": return SWITCH;
		case "true": return TRUE;
		case "try": return TRY;
		case "var": return VAR;
		case "while": return WHILE;
		case "extern": return EXTERN;
		case "inline": return INLINE;
		case "tlocal": return TLOCAL;
		// Base
		case "void": return VOID_TYPE;
		case "bool": return BOOL_TYPE;
		case "char": return CHAR_TYPE;
		case "ichar": return ICHAR_TYPE;
		case "short": return SHORT_TYPE;
		case "ushort": return USHORT_TYPE;
		case "int": return INT_TYPE;
		case "uint": return UINT_TYPE;
		case "long": return LONG_TYPE;
		case "ulong": return ULONG_TYPE;
		case "int128": return INT128_TYPE;
		case "uint128": return UINT128_TYPE;
		case "iptr": return IPTR_TYPE;
		case "uptr": return UPTR_TYPE;
		case "sz": return SZ_TYPE;
		case "usz": return USZ_TYPE;
		case "float": return FLOAT_TYPE;
		case "double": return DOUBLE_TYPE;
		case "float16": return FLOAT16_TYPE;
		case "bfloat": return BFLOAT_TYPE;
		case "float128": return FLOAT128_TYPE;
		case "fault": return FAULT_TYPE;
		case "typeid": return TYPEID_TYPE;
		default: return IDENT;
	}
}

fn Token lex_identifier(Lexer* self)
{
	Location start = self.location;
	int start_index = self.index;
	char first = self.current;

	if (first == '@' || first == '$' || first == '#')
	{
		advance(self);
	}

	while (self.current != 0 && is_ident(self.peek()))
	{
		advance(self);
	}

	int length = self.index - start_index;
	if (length <= 0)
	{
		diagnostics::error(self.ctx, 
		{ start, self.location }, 
		"Length of identifier was less or eq to 0");
		return {
			.kind = kind,
			.value = "<error>",
			.range = {
				.start = start,
				.end = self.location
			}
		};
	}

	String text = self.buffer[start_pos:length];

	TokenKind kind = self.categorize_identifier(text);

	return {
		.kind = kind,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token? lex_number(Lexer* self, int start_pos)
{
	Location start = self.location;
	int start_index = self.index;
	TokenKind kind = INT_DECIMAL_LITERAL;

	// Hex: 0x
	if (self.current == '0' && (ascii::to_lower(self.peek()) == 'x'))
	{
		kind = INT_HEX_LITERAL;
		self.advance(2)!;
		// Allow hex digits OR underscores
		while (self.current != 0 && (ascii::is_xdigit(self.current) || self.current == '_'))
		{
			advance(self);
		}

		if (self.current != 0 && self.current == '.' && self.peek() != '.') // && ascii::is_xdigit(self.peek_next()))
		{
			kind = FLOAT_HEX_LITERAL;
			advance(self);
			while (self.current != 0 && (ascii::is_xdigit(self.current) || self.current == '_'))
			{
				advance(self);
			}
		}

		if (!self.eof() && (self.current == 'p' || self.current == 'P'))
		{
			char next = self.peek();
			if (ascii::is_xdigit(next) || next == '-' || next == '+')
			{
				kind = FLOAT_HEX_LITERAL;
				advance(self);
				if (next == '-' || next == '+') advance(self);
				while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
				{
					advance(self);
				}
			}
		}
	} // Binary: 0b
	else if (self.current == '0' && (ascii::to_lower(self.peek()) == 'b'))
	{
		kind = INT_BIN_LITERAL;
		advance(self, 2);
		while (self.current != 0 && (ascii::is_bdigit(self.current) || self.current == '_'))
		{
			advance(self);
		}
	} // Octal: 0o
	else if (self.current == '0' && (ascii::to_lower(self.peek()) == 'o'))
	{
		kind = INT_OCTAL_LITERAL;
		advance(self, 2)!;
		while (self.current != 0 && (ascii::is_odigit(self.peek()) || self.peek() == '_'))
		{
			advance(self);
		}
	}
	else
	{
		kind = INT_DECIMAL_LITERAL;

		// Standard Decimals
		while (self.current != 0 && (ascii::is_digit(self.current) || self.current == '_'))
		{
			advance(self);
		}

		// Real/Float check
		if (self.current != 0 && self.current == '.' && self.peek() != '.') // && ascii::is_digit(self.peek_next()))
		{
			kind = FLOAT_DECIMAL_LITERAL;
			advance(self);
			while (self.current != 0 && (ascii::is_digit(self.current) || self.current == '_'))
			{
				advance(self);
			}
		}

		if (self.current != 0 && (self.current == 'e' || self.current == 'E'))
		{
			char next = self.peek();
			if (ascii::is_digit(next) || next == '-' || next == '+')
			{
				kind = FLOAT_DECIMAL_LITERAL;
				advance(self);
				if (next == '-' || next == '+') advance(self);
				while (self.current != 0 && (ascii::is_digit(self.current) || self.current == '_'))
				{
					advance(self);
				}
			}
		}
	}

	// Handle Suffixes (e.g., 1u, 1.0f, 0xFFu64) 
	char c = (char)ascii::to_lower(self.current);
	if (c == 'u' || c == 'i' || c == 'f' || c == 'l')
	{
		advance(self);
		while (self.current != 0 && ascii::is_alnum(self.current))
		{
			advance(self);
		}
	}

	return {
		.kind = kind,
		.value = self.get_string(stat, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token? lex_hex_array(Lexer* self, int start_pos)
{
	Location start = self.location;
	int start_index = self.index;
	char start_quote = self.peek();
	advance(self);

	int digit_count = 0;

	while (self.current != 0)
	{
		char c = self.current;

		if (c == start_quote)
		{
			advance(self);
			break;
		}

		if (c.is_whitespace())
		{
			advance(self);
			continue;
		}

		if (is_hex(c))
		{
			advance(self);
			digit_count++;
			continue;
		}

		diagnostics::error("[Lexer]: Unexpected character '%c' in hex string %s", c, self.index);
		return {
			.kind = ERROR,
			.value = self.get_string(start_index, self.index - start_index),
			.range = {
				.start = start,
				.end = self.location
			}
		};
	}

	if (digit_count % 2 != 0)
	{
		diagnostics::error(self.ctx, {  }, "[Lexer]: The hexadecimal string is not an even length");
		return {
			.kind = ERROR,
			.value = self.get_string(start_index, self.index - start_index),
			.range = {
				.start = start,
				.end = self.location
			}
		};
	}

	return {
		.kind = BYTES_LITERAL,
		.value = self.get_string(start_index, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn Token skip_contract(Lexer* self)
{
	Location start = self.location;
	int start_index = self.index;
	while (!self.eof())
	{
		char c = self.peek();
		if (c == '*' && self.peek(1) == '>')
		{
			self.advance(2);
			return {
				.kind = BYTES_LITERAL,
				.value = self.get_string(start_index, self.index - start_index),
				.range = {
					.start = start,
					.end = self.location
				}
			};
		}
		advance(self);
	}

	diagnostics::error(self.ctx, { start, self.location }, "Contract not closed");
	return {
		.kind = BYTES_LITERAL,
		.value = self.get_string(start_index, self.index - start_index),
		.range = {
			.start = start,
			.end = self.location
		}
	};
}

fn void advance(Lexer* self, int len = 1)
{
	self.index += len;
	if (self.index < self.buffer.len) 
	{
		self.current = self.buffer[self.index];
	} 
	else 
	{
		self.current = 0;
	}
}

fn Token Lexer.emit(&self, TokenKind kind, String value)
{
	Range start = self.range;
	Range end = {
		.lind = start.line,
		.column = start.column + value.len
	};

	return {
		.kind = kind,
		.range = {
			.start = start,
			.end = end
		},
		.value = value
	};
}

fn void tokenize(Lexer* lexer)
{
	while (lexer.current != 0)
	{	
		Token t = next(lexer);
		lexer.tokens.push(t);
		if (t.kind == EOF) break;
	}
}

fn Token next(Lexer* lexer)
{
	skip_whitespace(lexer);

	switch (lexer.current)
	{
		case 0: break;
		case '=':
			switch (lexer.peek(1))
			{
				case '=': return lexer.emit(EQEQ, "==");
				case '>': return lexer.emit(IMPLIES, "=>");
				default:
			}
			return lexer.emit(EQ, "=");
		case '|':
			switch (lexer.peek(1))
			{
				case '|':
					if (lexer.peek(2) == '|')
					{
						return lexer.emit(CT_OR_OP, "|||");
					}
					return lexer.emit(OR, "||");
				case '=': return lexer.emit(BIT_OR_ASSIGN, "|=");
			}
			return lexer.emit(BIT_OR, "|");
		case '!':
			switch (lexer.peek())
			{
				case '!': return lexer.emit(BANGBANG, "!!");
				case '=': return lexer.emit(NOT_EQUAL, "!=");
			}
			return lexer.emit(BANG, "!");
		case ':':
			if (lexer.peek() == ':')
			{
				return lexer.emit(SCOPE, start, 2);
			}
			return lexer.emit(COLON, start, 1);
		case '[':
			if (lexer.peek() == '<')
			{
				return lexer.emit(LVEC, "[<");
			}
			return lexer.emit(LBRACKET, "[");
		case ']':
			return lexer.emit(RBRACKET, "]");
		case '>':
			switch (lexer.peek(1))
			{
				case '>':
					if (lexer.peek(2) == '=')
					{
						return lexer.emit(RSHIFT_ASSIGN, ">>=");
					}
					return lexer.emit(RSHIFT, start, 2);
				case '=': return lexer.emit(GREATER_EQ, ">=");
				case ']': return lexer.emit(RVEC, "]");
			}
			return lexer.emit(GREATER, ">");
		case '<':
			switch (lexer.peek())
			{
				case '<':
					if (lexer.peek() == '=')
					{
						return lexer.emit(LSHIFT_ASSIGN, "<<=");
					}
					return lexer.emit(LSHIFT, "<<");
				case '=': return lexer.emit(LESS_EQ, "<=");
				case '*': return skip_contract(lexer);
			}
			return lexer.emit(LESS, "<");
		case '&':
			switch (lexer.peek())
			{
				case '&':
				{
					if (lexer.peek(2) == '&')
					{
						return lexer.emit(CT_AND_OP, "&&&");
					}

					return lexer.emit(AND, "&&");
				}
				case '=': return lexer.emit(BIT_AND_ASSIGN, "&=");
			}
			return lexer.emit(AMP, "&");
		case '*':
			switch (lexer.peek())
			{
				case '=': return lexer.emit(MULT_ASSIGN, "*=");
			}
			return lexer.emit(ASTERISK, "*");
		case '?':
			switch (lexer.peek())
			{
				case '?':
					if (lexer.peek(2) == '?')
					{
						return lexer.emit(CT_TERNARY, "???");
					}
					return lexer.emit(QUESTQUEST, "??");
				case ':': return lexer.emit(ELVIS, "?:");
			}
			return lexer.emit(QUESTION, "?");
		case '.':
			if (lexer.peek() == '.')
			{
				if (lexer.peek(2) == '.')
				{
					return lexer.emit(ELLIPSIS, "...");
				}

				return lexer.emit(DOTDOT, "..");
			}
			return lexer.emit(DOT, start, 1);
		case '%':
			if (lexer.peek() == '=')
			{
				return lexer.emit(MOD_ASSIGN, "%=");
			}
			return lexer.emit(MOD, "%");
		case '^':
			if (lexer.peek() == '=')
			{
				return lexer.emit(BIT_XOR_ASSIGN, "^=");
			}
			return lexer.emit(BIT_XOR, "^");
		case '+':
			switch (lexer.peek())
			{
				case '+':
				{
					if (lexer.peek(2) == '+')
					{
						if (lexer.peek(3) == '=')
						{
							return lexer.emit(CT_CONCAT_ASSIGN, "+++=");
						}
						return lexer.emit(CT_CONCAT_OP, "+++");
					}
					return lexer.emit(PLUSPLUS, "++");
				}
				case '=':
					return lexer.emit(PLUS_ASSIGN, "+=");
			}
			return lexer.emit(PLUS, "+");
		case '-':
			switch (lexer.peek())
			{
				case '-': return lexer.emit(MINUSMINUS, "--");
				case '=': return lexer.emit(MINUS_ASSIGN, "-=");
				case '>': return lexer.emit(ARROW, "->");
			}
			return lexer.emit(MINUS, "-");
		case '~': return lexer.emit(BIT_NOT, "~");
		case '(': return lexer.emit(LPAREN, "(");
		case ')': return lexer.emit(RPAREN, ")");
		case '{': return lexer.emit(LBRACE, "{");
		case '}': return lexer.emit(RBRACE, "}");
		case ';': return lexer.emit(EOS, ";");
		case ',': return lexer.emit(COMMA, ",");
		case '/':
			switch (lexer.peek(1))
			{
				case '/': return lex_line_comment(lexer);
				case '*': return lex_block_comment(lexer);
				case '=': return lexer.emit(DIV_ASSIGN, "/=");
				default: break;
			}
			return lexer.emit(DIV, "/");
		case '\'':
			return lex_char(lexer);
		case '"':
			return lex_string(lexer);
		case '`':
			return lex_raw_string(lexer);
		case '$':
			if (lexer.peek(1) == '$')
			{
				return lexer.emit(BUILTIN, "$$");
			}
			nextcase;
		case 'b':
			if (lexer.peek(1) == '6' && lexer.peek(2) == '4' && (lexer.peek(3) == '`' || lexer.peek(3) == '"'))
			{
				Location start = lexer.location;
				int start_index = lexer.index;
				char quote_char = lexer.peek(3);
				advance(lexer, 4)!;
				while (lexer.current != 0)
				{
					if (lexer.current == quote_char)
					{
						advance(lexer); // Advance past the closing quote
						return {
							.kind = BYTES_LITERAL,
							.range = {
								.start = start,
								.end = lexer.location
							},
							.value = lexer.get_string(start_index, lexer.index - start_index)
						};
					}
					advance(lexer);
				}
				return emit(ERROR, "");
			}
			nextcase;
		case 'x':
			if (lexer.peek(1) == '"' || lexer.peek(1) == '\'' || lexer.peek(1) == '`')
			{
				return lex_hex_array(lexer)!;
			}
			nextcase;
		case '@':
		case '#':
			return lex_identifier(lexer);
		default:
			if (is_digit(c)) return lex_number(lexer);
			if (is_ident(c)) return lex_identifier(lexer);
			break;
	}

	return {
		.kind = EOF,
		.range = {
			.start = lexer.location,
			.end = lexer.location
		},
		.value = "<EOF>"
	};
}

fn TokenKind categorize_identifier(Lexer* self, String text)
{
	if (text.len == 0) return ERROR;

	char prefix     = text[0];
	String base;
	bool has_prefix = false;

	if (prefix == '@' && text.len == 1)
	{
		return AT;
	}

	if (prefix == '@' || prefix == '$' || prefix == '#')
	{
		base = text[1:text.len - 1];
		has_prefix = true;

		if (prefix == '$')
		{
			switch (base)
			{
				case "assert": return CT_ASSERT;
				case "case": return CT_CASE;
				case "default": return CT_DEFAULT;
				case "defined": return CT_DEFINED;
				case "echo": return CT_ECHO;
				case "expand": return CT_EXPAND;
				case "else": return CT_ELSE;
				case "endfor": return CT_ENDFOR;
				case "endforeach": return CT_ENDFOREACH;
				case "endif": return CT_ENDIF;
				case "endswitch": return CT_ENDSWITCH;
				case "error": return CT_ERROR;
				case "eval": return CT_EVAL;
				case "exec": return CT_EXEC;
				case "feature": return CT_FEATURE;
				case "for": return CT_FOR;
				case "foreach": return CT_FOREACH;
				case "if": return CT_IF;
				case "include": return CT_INCLUDE;
				case "reflect": return CT_REFLECT;
				case "stringify": return CT_STRINGIFY;
				case "switch": return CT_SWITCH;
				case "Typefrom": return CT_TYPEFROM;
				case "Typeof": return CT_TYPEOF;
				case "vaarg": return CT_VAARG;
				default: break;
			}
		}
	}
	else
	{
		base = text;
		TokenKind kind = lookup_keyword(base);
		if (kind != IDENT) return kind;
	}
	
	

	while (base.len > 0 && base[0] == '_')
	{
		base = base[1..];
	}

	bool is_type  = false;
	bool is_const = false;

	if (base.len > 0)
	{
		char first_char = base[0];
		if (first_char >= 'A' && first_char <= 'Z')
		{
			if (is_all_upper(base))
			{
				is_const = true;
			}
			else
			{
				is_type = true;
			}
		}
	}

	if (prefix == '@')
	{
		if (is_const) return AT_CONST_IDENT;
		if (is_type) return AT_TYPE_IDENT;
		return AT_IDENT;
	}
	if (prefix == '$')
	{
		if (is_const) return CT_CONST_IDENT;
		if (is_type) return CT_TYPE_IDENT;
		return CT_IDENT;
	}
	if (prefix == '#')
	{
		if (is_const) return HASH_CONST_IDENT;
		if (is_type) return HASH_TYPE_IDENT;
		return HASH_IDENT;
	}

	if (is_const) return CONST_IDENT;
	if (is_type) return TYPE_IDENT;
	return IDENT;
}

struct ContractLexer
{
	Lexer lexer;
	String description;
	int desc_len;
}

<*
 @require contract.len >= 4 : "Contract must contain at least 4 chars"
*>
fn void ContractLexer.init(&self, String contract)
{
	// Strip the decorators <* and *>
	String inner = contract[2:^4];
	plog::debug("ContractLexer - string = %s", inner);

	sz i              = 0;
	bool line_start    = true;
	sz first_at_index = inner.len;

	// Scan for the first '@' that starts a line
	while (i < inner.len)
	{
		char c = inner[i];

		if (c == '@' && line_start)
		{
			first_at_index = i;
			break;
		}

		if (c == '\n')
		{
			line_start = true;
		}
		else if (!char.is_blank(c))
		{
			line_start = false;
		}

		i++;
	}

	self.description = inner[0:first_at_index].trim();
	self.desc_len = (int)first_at_index;

	self.lexer = { .buffer = inner[first_at_index..], .index = 0 };
	plog::debug("ContractLexer - buffer = %s", self.lexer.buffer);
}

fn Token? ContractLexer.next(&self) => self.lexer.next();

fn void test_lexer() @test
{
	String src  = "module foo; \nfn void bar() {}";
	Lexer lexer = (Lexer) { .buffer = src, .index = 0, };

	while (!lexer.eof())
	{
		Token token = lexer.next()!;
		io::printfn("token: %s", lexer.buffer[token.pos:token.len]);
	}
}
