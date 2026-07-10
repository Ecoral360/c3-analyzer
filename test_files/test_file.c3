module 

fn int main()
{
    return 0;
}

macro @foo($x, #y)
{
    $switch:
        $case $x > 10:
            #y += $x * $x;
        $case $x < 0:
            #y += $x;
        $default:
            #y -= $x;
    $endswitch
}