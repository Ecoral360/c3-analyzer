module hello; 

fn void foo()
{    
    String src = ctx.section.source_file.source;
    Lexer lexer = { .buffer = src };
}