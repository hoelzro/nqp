use QASTNode;

# The different types of js things a Chunk expr can be
my $T_OBJ  := 0; 
my $T_INT  := 1; # We use a javascript number but always treat it as a 32bit integer
my $T_NUM  := 2; # We use a javascript number for that
my $T_STR  := 3; # We use a javascript str for that
my $T_BOOL := 4; # Something that can be used in boolean context in javascript. To the user it should be presented as a 0 or 1
my $T_VOID := -1; # Value of this type shouldn't exist, we use a "" as the expr
my $T_NONVAL := -2; # something that is not a nqp value

# turn a string into a javascript literal
sub quote_string($str) {
    # This could be simplified a lot when running on none-parrot nqps, as most of the complexity is required to transform \x{...}  which is parrot nqp::escape specific

    my $out := '';
    my $quoted := nqp::escape($str);

    # We use a lot of variables to keep track of the state as we can only iterate the chars sequentialy
    # nqp::escape on nqp-p returns \x{..} on parrot which we have to transform 
    my $backslash := 0;
    my $x := 0;
    my $curly := 0;

    my $escape := '';

    for nqp::split('',$quoted~'') -> $c {
        if $backslash && $c eq 'e' {
            $out := $out ~ 'x1b';
        } elsif $backslash && $c eq 'a' {
            $out := $out ~ 'x07';
        } elsif $backslash && $c eq 'x' {
            $x := 1;
        } elsif $x && $c eq '{' {
            $x := 0;
            $curly := 1;
        } elsif $curly && $c eq '}' {
           $out := $out ~ 'u'~nqp::x("0",4-nqp::chars($escape))~$escape;
           $escape := '';
           $curly := 0;
        } elsif $curly {
            $escape := $escape ~ $c;
        } else {
            $out := $out ~ $c;
        }
        $backslash := !$backslash && $c eq '\\';
    }
    "\""~$out~"\"";
}

class Chunk {
    has int $!type; # the js type of $!expr
    has str $!expr; # a javascript expression without side effects
    has $!node; # a QAST::Node that contains info for source maps
    has @!setup; # stuff that needs to be executed before the value of $!expr can be used, this contains strings and Chunks.

    method new($type, $expr, @setup, :$node) {
        my $obj := nqp::create(self);
        $obj.BUILD($type, $expr, @setup, :$node);
        $obj
    }

    method BUILD($type, $expr, @setup, :$node) {
        $!type := $type;
        $!expr := $expr;
        @!setup := @setup;
        $!node := $node if nqp::defined($node);
    }

    method join() {
        my $js := ''; 
        for @!setup -> $part {
           if nqp::isstr($part) {
              $js := $js ~ $part;
           } else {
              $js := $js ~ $part.join;
           }
        }
        $js;
    }
    
    method with_source_map_info() {
        my @parts;
        for @!setup -> $part {
            if nqp::isstr($part) {
                nqp::push(@parts,quote_string($part));
            } else {
                nqp::push(@parts,$part.with_source_map_info);
            }
        }
        my $parts := '[' ~ nqp::join(',', @parts) ~ ']';
        if nqp::defined($!node) && $!node.node {
            my $node := $!node.node;
            my $line := HLL::Compiler.lineof($node.orig(), $node.from(), :cache(1));
            "\{\"line\": $line, \"parts\": $parts\}";
        } else {
            $parts;
        }
    }

    method type() {
        $!type;
    }

    method expr() {
        $!expr;
    }

    method setup() {
        @!setup;
    }
}


# TODO think if we should be using such a complicated name mangling scheme
# It's separated into a role so we may replace it with an different scheme when we won't to reduce the output size
role DWIMYNameMangling {
    # List taken from https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Reserved_Words
    my %reserved_words;
    for nqp::split(" ",'break case catch continue debugger default delete do else finally for function if in instanceof new return switch this throw try typeof var void while with implements interface let package private protected public static yield class enum export extends import super') {
        %reserved_words{$_} := 1;
    }
    method is_reserved_word($identifier) {
        nqp::existskey(%reserved_words, $identifier);
    }

    my %mangle;
    %mangle<_> := 'UNDERSCORE';
    %mangle<&> := 'AMPERSAND';
    %mangle<:> := 'COLON';
    %mangle<;> := 'SEMI';
    %mangle<<> := 'LESS';
    %mangle<>> := 'MORE';
    %mangle<{> := 'CURLY_OPEN';
    %mangle<}> := 'CURLY_CLOSE';
    %mangle<[> := 'BRACKET_OPEN';
    %mangle<]> := 'BRACKET_CLOSE';
    %mangle<(> := 'PAREN_OPEN';
    %mangle<)> := 'PAREN_CLOSE';
    %mangle<~> := 'TILDE';
    %mangle<+> := 'PLUS';
    %mangle<=> := 'EQUAL';
    %mangle<?> := 'QUESTION';
    %mangle<!> := 'BANG';
    %mangle</> := 'SLASH';
    %mangle<*> := 'STAR';
    %mangle<-> := 'MINUS';
    %mangle<@> := 'AT';
    %mangle<,> := 'COMMA';
    %mangle<%> := 'PERCENT';
    %mangle<¢> := 'CENT';
    %mangle< > := 'SPACE';
    %mangle<'> := 'SINGLE';
    %mangle<"> := 'QUOTE';
    %mangle<^> := 'CARET';
    %mangle<.> := 'DOT';
    %mangle<|> := 'PIPE';
    %mangle<`> := 'BACKTICK';
    %mangle<$> := 'DOLLAR';
    %mangle<\\> := 'BACKSLASH';

    method mangle_name($name) {
        if self.is_reserved_word($name) {$name := "_$name"}

        my $mangled := '';

        for nqp::split('',$name) -> $char {
            if nqp::iscclass(nqp::const::CCLASS_ALPHANUMERIC, $char, 0) {
                $mangled := $mangled ~ $char;
            } else {
                if nqp::existskey(%mangle, $char) {
                    $mangled := $mangled ~ '_' ~ %mangle{$char} ~ '_';
                } else {
                    $mangled := $mangled ~ '_' ~ nqp::ord($char) ~ '_';
                }
            }
        }

        $mangled;
    }
}

class QAST::OperationsJS {
    my %ops;


    sub add_op($op, $cb) {
        %ops{$op} := $cb;
    }

    sub add_infix_op($op, $left_type, $syntax, $right_type, $return_type) {
        %ops{$op} := sub ($comp, $node, :$want) {
            my $left  := $comp.as_js($node[0], :want($left_type));
            my $right := $comp.as_js($node[1], :want($right_type));
            Chunk.new($return_type, "({$left.expr} $syntax {$right.expr})", [$left, $right], :$node);
        };
    }

    add_infix_op('add_n', $T_NUM, '+', $T_NUM, $T_NUM);
    add_infix_op('sub_n', $T_NUM, '-', $T_NUM, $T_NUM);
    add_infix_op('mul_n', $T_NUM, '*', $T_NUM, $T_NUM);
    # TODO - think about divide by zero
    add_infix_op('div_n', $T_NUM, '/', $T_NUM, $T_NUM);

    add_op('neg_n', sub ($comp, $node, :$want) {
        my $num := $comp.as_js($node[0], :want($T_NUM));
        Chunk.new($T_INT, "(-{$num.expr})" , [$num], :$node);
    });

    add_infix_op('concat', $T_STR, '+', $T_STR, $T_STR);

    add_infix_op('isle_n', $T_NUM, '<=', $T_NUM, $T_BOOL);
    add_infix_op('iseq_n', $T_NUM, '==', $T_NUM, $T_BOOL);
    add_infix_op('isne_n', $T_NUM, '!=', $T_NUM, $T_BOOL);

    add_infix_op('iseq_s', $T_STR, '==', $T_STR, $T_BOOL);
    add_infix_op('isne_s', $T_STR, '!=', $T_STR, $T_BOOL);

    add_infix_op('eqaddr', $T_OBJ, '===', $T_OBJ, $T_BOOL);

    sub add_cmp_op($op, $type) {
        %ops{$op} := sub ($comp, $node, :$want) {
            my $a  := $comp.as_js($node[0], :want($type));
            my $b := $comp.as_js($node[1], :want($type));
            Chunk.new($T_INT, "({$a.expr} < {$b.expr} ? -1 : ({$a.expr} == {$b.expr} ? 0 : 1))", [$a, $b], :$node);
        };
    }

    add_cmp_op('cmp_i', $T_INT);
    add_cmp_op('cmp_n', $T_NUM);
    add_cmp_op('cmp_s', $T_STR);

    add_op('chars', sub ($comp, $node, :$want) {
        my $arg := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_INT, "{$arg.expr}.length" , [$arg], :$node);
    });

    add_op('join', sub ($comp, $node, :$want) {
        my $delim := $comp.as_js($node[0], :want($T_STR));
        my $list := $comp.as_js($node[1], :want($T_OBJ));
        Chunk.new($T_STR, "{$list.expr}.join({$delim.expr})" , [$delim, $list], :$node);
    });

    add_op('index', sub ($comp, $node, :$want) {
        my $string := $comp.as_js($node[0], :want($T_STR));
        my $pattern := $comp.as_js($node[1], :want($T_STR));
        if +$node.list == 2 {
            Chunk.new($T_INT, "{$string.expr}.indexOf({$pattern.expr})" , [$string, $pattern], :$node);
        } else {
            my $starting := $comp.as_js($node[2], :want($T_INT));
            Chunk.new($T_INT, "{$string.expr}.indexOf({$pattern.expr},{$starting.expr})" , [$string, $pattern, $starting], :$node);
        }
    });

    add_op('chr', sub ($comp, $node, :$want) {
        my $code := $comp.as_js($node[0], :want($T_INT));
        Chunk.new($T_STR, "String.fromCharCode({$code.expr})" , [$code], :$node);
    });

    add_op('lc', sub ($comp, $node, :$want) {
        my $string := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_STR, "{$string.expr}.toLowerCase()" , [$string], :$node);
    });
    add_op('uc', sub ($comp, $node, :$want) {
        my $string := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_STR, "{$string.expr}.toUpperCase()" , [$string], :$node);
    });

    add_op('flip', sub ($comp, $node, :$want) {
        my $string := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_STR, "{$string.expr}.split('').reverse().join('')" , [$string], :$node);
    });

    add_op('ord', sub ($comp, $node, :$want) {
        my $string := $comp.as_js($node[0], :want($T_STR));
        if +$node.list == 1 {
            Chunk.new($T_INT, "{$string.expr}.charCodeAt(0)" , [$string], :$node);
        } else {
            my $pos := $comp.as_js($node[1], :want($T_INT));
            Chunk.new($T_INT, "{$string.expr}.charCodeAt({$pos.expr})" , [$string, $pos], :$node);
        }
    });

    add_op('null', sub ($comp, $node, :$want) {
        Chunk.new($T_OBJ, "null" , [], :$node);
    });

    add_op('getcomp', sub ($comp, $node, :$want) {
        my $arg := $comp.as_js($node[0], :want($T_STR));
        my $tmp := $*BLOCK.add_tmp();
        Chunk.new($T_OBJ, $tmp , [$arg, "$tmp = nqp.op.getcomp({$arg.expr});\n"], :$node);
    });

    add_op('say', sub ($comp, $node, :$want) {
        my $arg := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_VOID, "" , [$arg, "nqp.op.say({$arg.expr});\n"], :$node);
    });

    add_op('print', sub ($comp, $node, :$want) {
        my $arg := $comp.as_js($node[0], :want($T_STR));
        Chunk.new($T_VOID, "" , [$arg, "nqp.op.print({$arg.expr});\n"], :$node);
    });

    add_op('isinvokable', sub ($comp, $node, :$want) {
        my $arg := $comp.as_js($node[0], :want($T_OBJ));
        Chunk.new($T_INT, "nqp.op.isinvokable({$arg.expr})" , [$arg], :$node);
    });

    # TODO - think if it's the correct thing to do
    add_op('takeclosure', sub ($comp, $node, :$want) {
        $comp.as_js($node[0], :want($T_OBJ));
    });

    add_op('istrue', sub ($comp, $node, :$want) {
        $comp.as_js($node[0], :want($T_BOOL));
    });
    add_op('stringify', sub ($comp, $node, :$want) {
        $comp.as_js($node[0], :want($T_STR));
    });
    add_op('numify', sub ($comp, $node, :$want) {
        $comp.as_js($node[0], :want($T_NUM));
    });

    add_op('falsey', sub ($comp, $node, :$want) {
        my $boolified := $comp.as_js($node[0], :want($T_BOOL));
        Chunk.new($T_BOOL, "(!{$boolified.expr})", [$boolified]);
    });

    add_op('bind', sub ($comp, $node, :$want) {
        my @children := $node.list;
        if +@children != 2 {
            nqp::die("A 'bind' op must have exactly two children");
        }
        unless nqp::istype(@children[0], QAST::Var) {
            nqp::die("First child of a 'bind' op must be a QAST::Var");
        }

        # TODO take the type of variable into account
        my $*BINDVAL := @children[1];
        $comp.as_js(@children[0], :want($T_OBJ));
    });

    add_op('list', sub ($comp, $node, :$want) {
       my @setup;
       my @exprs;

       for $node.list -> $elem {
           my $chunk := $comp.as_js($elem, :want($T_OBJ));
           @setup.push($chunk);
           @exprs.push($chunk.expr);
       }

       Chunk.new($T_OBJ, '[' ~ nqp::join(',', @exprs) ~ ']' , @setup, :$node);
    });

    add_op('call', sub ($comp, $node, :$want) {
        my $tmp := $*BLOCK.add_tmp();

        my $args := nqp::clone($node.list);

        my $callee := $node.name
            ?? $comp.as_js(QAST::Var.new(:name($node.name),:scope('lexical')), :want($T_OBJ))
            !! $comp.as_js(nqp::shift($args), :want($T_OBJ));

        my $compiled_args := $comp.args($args);

        if nqp::islist($compiled_args) {
            my @exprs;
            my @setup := [$callee];
            for $compiled_args -> $group {
                @exprs.push($group.expr);
                @setup.push($group);
            }
            @setup.push("$tmp = {$callee.expr}({@exprs.shift ~ '.concat(' ~ nqp::join(',', @exprs)}));\n");
            Chunk.new($T_OBJ, $tmp , @setup, :$node);
        } else {
            Chunk.new($T_OBJ, $tmp , [$callee, $compiled_args, "$tmp = {$callee.expr}({$compiled_args.expr});\n"], :$node);
        }
    });

    add_op('split', sub ($comp, $node, :$want) {
        my $separator := $comp.as_js($node[0], :want($T_STR));
        my $string := $comp.as_js($node[1], :want($T_STR));
        Chunk.new($T_OBJ, "({$string.expr} == '' ? [] : {$string.expr}.split({$separator.expr}))" , [$string, $separator], :$node);
    });

    add_op('elems', sub ($comp, $node, :$want) {
        my $list := $comp.as_js($node[0], :want($T_OBJ));
        Chunk.new($T_INT, "({$list.expr}.length)" , [$list], :$node);
    });

    add_op('islist', sub ($comp, $node, :$want) {
        my $obj := $comp.as_js($node[0], :want($T_OBJ));
        Chunk.new($T_BOOL, "({$obj.expr} instanceof Array)" , [$obj], :$node);
    });

    for <ceil floor abs> -> $func {
        add_op($func ~ '_n', sub ($comp, $node, :$want) {
            my $arg := $comp.as_js($node[0], :want($T_NUM));
            Chunk.new($T_NUM, "Math.$func({$arg.expr})" , [$arg], :$node);
        });
    }

    for <if unless> -> $op_name {
        add_op($op_name, sub ($comp, $node, :$want) {
            unless nqp::defined($want) {
                nqp::die("Unknown want");
            }

            my $operands := +$node.list;
            nqp::die("Operation '"~$node.op~"' needs either 2 or 3 operands")
                if $operands < 2 || $operands > 3;

            # The 2 operand form of if in a non-void context also uses the cond as the return value
            my $cond := $comp.as_js($node[0], :want( ($operands == 3 || $want == $T_VOID) ?? $T_BOOL !! $want));
            my $then;
            my $else;

            my $result;

            if $want != $T_VOID {
                $result := $*BLOCK.add_tmp();
            }

            # See if any immediate block wants to be passed the condition.
            my $im_then := (nqp::istype($node[1], QAST::Block) && 
                           $node[1].blocktype eq 'immediate' &&
                           $node[1].arity > 0) ?? 1 !! 0;
            my $im_else := ($operands == 3 &&
                           nqp::istype($node[2], QAST::Block) && 
                           $node[2].blocktype eq 'immediate' &&
                           $node[2].arity > 0) ?? 1 !! 0;

            # TODO if cond() -> $var {...}

            my $boolifed_cond := $comp.coerce($cond, $T_BOOL);


            if $node.op eq 'if' {
                $then := $comp.as_js($node[1], :$want);

                if $operands == 3 {
                    $else := $comp.as_js($node[2], :$want);
                } else {
                    $else := $comp.coerce($cond, $want);
                }
            } else {
                if $operands == 3 {
                    $then := $comp.as_js($node[2], :$want);
                } else {
                    $then := $comp.coerce($cond, $want);
                }
                $else := $comp.as_js($node[1], :$want);
            }


            Chunk.new($want, $result, [
                $boolifed_cond,
                "if ({$boolifed_cond.expr}) \{",
                $then,
                $want != $T_VOID ?? "$result = {$then.expr}" !! '',
                "\} else \{",
                $else,
                $want != $T_VOID ?? "$result = {$else.expr}" !! '',
                "\}"
            ], :node($node));
        });
    }

    method compile_op($comp, $op, :$want) {
        my str $name := $op.op;
        if nqp::existskey(%ops, $name) {
            %ops{$name}($comp, $op, :$want);
        } else {
            $comp.NYI("unimplemented QAST::Op {$op.op}");
        }
    }
}

class QAST::CompilerJS does DWIMYNameMangling {

    # Holds information about the QAST::Block we're currently compiling.
    # The currently compiled block is stored in $*BLOCK
    my class BlockInfo {
        has $!qast;             # The QAST::Block
        has $!outer;            # Outer block's BlockInfo
        has @!js_lexicals;      # javascript variables we need to declare for the block
        has $!tmp;              # We use a bunch of TMP{$n} to store intermediate javascript results
        has $!ctx;              # The object we keep dynamic variables and exception handlers in
        has @!params;           # the parameters the block takes

        method new($qast, $outer) {
            my $obj := nqp::create(self);
            $obj.BUILD($qast, $outer);
            $obj
        }

        method BUILD($qast, $outer) {
            $!qast := $qast;
            $!outer := $outer;
            @!js_lexicals := nqp::list();
            @!params := nqp::list();
            $!tmp := 0;
        }

        method add_js_lexical($name) {
            @!js_lexicals.push($name);
        }

        method add_tmp() {
            $!tmp := $!tmp + 1;
            'TMP'~$!tmp;
        }

        method add_param($param) {
            @!params.push($param);
        }

        method tmps() {
            my @tmps;
            my $i := 1;
            while $i <= $!tmp {
                @tmps.push('TMP'~$i);
                $i := $i+1;
            }
            @tmps;
        }

        method js_lexicals() { @!js_lexicals }
        method outer() { $!outer }
        method qast() { $!qast }
        method ctx(*@value) { $!ctx := @value[0] if @value;$!ctx}
        method params() { @!params }
    }


    # TODO improve comments
    # turns a list of arguments for a call into a js code according to our most generall calling convention
    # $args is the list of QAST::Node arguments
    # returns either a js code string which contains the arguments, or a list of js code strings that when executed create arrays of arguments (suitable for concatenating and passing into Function.apply) 

    method args($args) {
        my @setup;
        my @args;
        my @named;
        my @flat_named;
        my @groups := [[]];
        for $args -> $arg {
            if nqp::istype($arg,QAST::SpecialArg) {
                if $arg.flat {
                    if $arg.named {
                        # TODO - think about chunks
                        @flat_named.push(self.as_js($arg));
                    } else {
                        @groups.push(self.as_js($arg, :want($T_OBJ)));
                        @groups.push([]);
                    }
                }
                elsif $arg.named {
                    # TODO - think about chunks
                    @named.push(self.quote_string($arg.named)~":"~self.as_js($arg))
                }
                else {
                    @groups[@groups-1].push(self.as_js($arg, :want($T_OBJ)));
                }
            } else {
                @groups[@groups-1].push(self.as_js($arg, :want($T_OBJ)));
            }
        }
        @flat_named.unshift('{'~nqp::join(',',@named)~'}');
        @groups[0].unshift("nqp.named({nqp::join(',',@flat_named)})");
        @groups[0].unshift($*BLOCK.ctx);

        my sub chunkify(@group, $pre = '', $post = '') {
            my @exprs;
            my @setup;
            for @group -> $arg {
                if nqp::isstr($arg) {
                    @exprs.push($arg);
                } else {
                    @exprs.push($arg.expr);
                    @setup.push($arg);
                }
            }
            Chunk.new($T_NONVAL, $pre ~ nqp::join(',', @exprs) ~ $post, @setup);
        } 

        if +@groups == 1 {
            return chunkify(@groups[0]);
        }

        my @js_args;
        for @groups -> $group {
            if nqp::islist($group) {
                @js_args.push(chunkify($group, '[', ']')) if +$group
            } else {
                @js_args.push($group);
            }
        }
        @js_args;
    }

    method compile_sig(@params) {
        my $slurpy_named; # *%foo
        my $slurpy;       # *@foo
        my @named;        # :$foo
        my @pos;          # $foo

        my $bind_named := '';
        for @params {
            if $_.slurpy {
                say("//NYI: slurpy params {$_.name}");
                if $_.named {
                    $slurpy_named := $_; 
                } else {
                    $slurpy := $_;
                }
            } elsif $_.named {
                say("//NYI: named params");
                unless self.is_dynamic_var($_) {
                    @named.push(self.mangle_name($_.name));
                }
                my $quoted := self.quote_string($_.named);
                my $value := "_NAMED[$quoted]";
                if $_.default {
                    $value := "(_NAMED.hasOwnProperty($quoted) ? $value : {self.as_js($_.default)})";
                }

                $bind_named := $bind_named ~ self.bind_var($_,self.js($value),1) ~ ";\n";
            } else {
                my $default := '';
                if $_.default {
                    say("//NYI: default");
                    $default := self.as_js($_.default, :want($T_OBJ));
                }
                @pos.push([$_,$default]);
            }
        }

#        if $slurpy_named {
#            $bind_named := $bind_named ~ self.bind_var($slurpy_named,self.js('_NAMED'),1) ~ ";\n";
#        }

        my @sig := ['_NAMED','caller_ctx'];

        for @pos -> $pos {
            @sig.push(self.mangle_name($pos[0].name));
        }

        nqp::join(',', @sig);
    }


    method coerce($chunk, $desired) {
        my $got := $chunk.type;
        if $got != $desired {
            if $desired == $T_NUM {
                if $got == $T_INT {
                    # we store both as a javascript number, and 32bit integers fit into doubles
                    return Chunk.new($T_NUM, $chunk.expr, [$chunk]);
                }
                if $got == $T_BOOL {
                    return Chunk.new($T_NUM, "({$chunk.expr} ? 1 : 0)", [$chunk]);
                }
                if $got == $T_STR {
                    my $tmp := $*BLOCK.add_tmp();
                    return Chunk.new($T_NUM, "(isNaN($tmp) ? 0 : $tmp)", [$chunk,"$tmp = parseFloat({$chunk.expr});\n"]);
                    return Chunk.new($T_NUM, $chunk.expr, [$chunk]);
                }
            }

            if $got == $T_OBJ {
                my %convert;
                %convert{$T_STR} := 'to_str';
                %convert{$T_NUM} := 'to_num';
                %convert{$T_INT} := 'to_int';
                %convert{$T_BOOL} := 'to_bool';
                return Chunk.new($desired, 'nqp.' ~ %convert{$desired} ~ '(' ~ $chunk.expr ~ ')', [$chunk]);
            }

            if $desired == $T_STR {
                if $got == $T_INT || $got == $T_NUM {
                    return Chunk.new($T_STR, $chunk.expr ~ '.toString()', [$chunk]);
                }
                if $got == $T_BOOL {
                    return Chunk.new($T_STR, "({$chunk.expr} ? '1' : '0')", [$chunk]);
                }
            }

            if $desired == $T_OBJ {
                if $got == $T_INT || $got == $T_NUM || $got == $T_STR {
                    return $chunk;
                } elsif $got == $T_BOOL {
                    return Chunk.new($T_OBJ, "({$chunk.expr} ? 1 : 0)", [$chunk]);
                } elsif $got == $T_VOID {
                    # TODO think what's the correct thing here
                    return Chunk.new($T_OBJ, "null", [$chunk]);
                }
            }

            if $desired == $T_BOOL {
                if $got == $T_INT || $got == $T_NUM {
                    return Chunk.new($T_BOOL, $chunk.expr, [$chunk]);
                } elsif $got == $T_STR {
                    return Chunk.new($T_BOOL, "({$chunk.expr} != '0' && {$chunk.expr})", [$chunk]);
                }
            }

            if $desired == $T_VOID {
                return Chunk.new($T_VOID, "", $chunk.setup);
            }

            return Chunk.new($desired, "coercion($got, $desired, {$chunk.expr})", []) #TODO
        }
        $chunk;
    }


    # It's more usefull for me during this development to emit partial code instead of quiting
    method NYI($msg) {
        Chunk.new($T_VOID,"NYI($msg)",["// NYI: $msg\n"]);
        #nqp::die("NYI: $msg");
    }


    method declare_js_vars(@vars) {
        if +@vars {
            'var '~nqp::join(",\n",@vars)~";\n";
        } else {
            '';
        }
    }

    sub want($node, $desired) {
        # TODO
    }

    proto method as_js($node, :$want) {
        unless nqp::defined($want) {
            nqp::die("Unknown want");
        }

        if nqp::defined($want) {
            if nqp::istype($node, QAST::Want) {
                self.NYI("QAST::Want");
#                self.coerce(self.as_jast(want($node, $*WANT)), $*WANT)
            }
            else {
                self.coerce({*}, $want)
            }
        }
        else {
            {*}
        }
    }


    # detect the result of HLL::Compiler.CTXSAVE, we need to handle this specially as for performance reasons we store some lexicals as actual javascript lexicals instead of on the context
    method is_ctxsave($node) {
        +$node.list == 2
        && nqp::istype($node[0], QAST::Op)
        && $node[0].op eq 'bind'
        && +$node[0].list == 2
        && nqp::istype($node[0][0], QAST::Var)
        && $node[0][0].name eq 'ctxsave';
    }

    # TODO save the value of the last statement
    method compile_all_the_statements(QAST::Stmts $node, $want, :$resultchild) {
        my @setup;
        my @stmts := $node.list;
        my int $n := +@stmts;

#        my $all_void := $*WANT == $T_VOID;

        unless nqp::defined($resultchild) {
            $resultchild := $n - 1;
        }

        my $result := "";

        my int $i := 0;
        for @stmts {
            my $chunk := self.as_js($_, :want($i == $resultchild ?? $want !! $T_VOID));
            $result := $chunk.expr if $i == $resultchild;
            nqp::push(@setup, $chunk);
            $i := $i + 1;
        }
        Chunk.new($want, $result, @setup);
    }

    multi method as_js(QAST::Block $node, :$want) {
        my $outer     := try $*BLOCK;
        self.compile_block($node, $outer, :$want);
    }

    method mangled_cuid($node) {
        my $ret := '';
        for nqp::split('',$node.cuid) -> $c {
            $ret := $ret ~ ($c eq '.' ?? '_' !! $c); 
        }
        $ret;
    }

    has %!cuids;

    method register_cuid($node) {
        %!cuids{$node.cuid} := 1;
    }

    method is_known_cuid($node) {
        nqp::existskey(%!cuids, $node.cuid);
    }

    method compile_block(QAST::Block $node, $outer, :$want) {
        my $cuid := self.mangled_cuid($node);

        my $setup;

        if self.is_known_cuid($node) {
            $setup := [];
        } else {
            self.register_cuid($node);
            my $*BINDVAL := 0;
            my $*BLOCK := BlockInfo.new($node, (nqp::defined($outer) ?? $outer !! NQPMu));

            my $create_ctx := self.create_fresh_ctx();

            # TODO proper want handling

            my $body_want := $T_OBJ;

            my $stmts := self.compile_all_the_statements($node, $body_want);

            my $sig := self.compile_sig($*BLOCK.params);

            $setup := [
                "$cuid = function($sig) \{",
                self.declare_js_vars($*BLOCK.tmps),
                self.declare_js_vars($*BLOCK.js_lexicals),
                $create_ctx,
                $stmts,
                "return {$stmts.expr};\n",
                "\};\n"];
        }

        if $node.blocktype eq 'immediate' {
            self.NYI("immediate blocks");
        } else {
            Chunk.new($T_OBJ, $cuid, $setup);
        }
    }

    has $!unique_vars;

    method unique_var($prefix) {
        $!unique_vars := $!unique_vars + 1;
        $prefix~$!unique_vars;
    }

    method create_fresh_ctx() {
        $*BLOCK.ctx(self.unique_var('ctx'));
        self.create_ctx($*BLOCK.ctx);
    }

    method create_ctx($name) {
        # TODO think about contexts
        #"var $name = new nqp.Ctx(caller_ctx,{self.outer_ctx},'$name');\n";
        "var $name = null;\n";
    }

    multi method as_js(QAST::IVal $node, :$want) {
        Chunk.new($T_INT,'('~$node.value()~')',[],:$node);
    }

    multi method as_js(QAST::NVal $node, :$want) {
        Chunk.new($T_NUM,'('~$node.value()~')',[],:$node);
    }

    multi method as_js(QAST::SVal $node, :$want) {
        Chunk.new($T_STR,quote_string($node.value()),[],:$node);
    }

    multi method as_js(QAST::BVal $node, :$want) {
        self.as_js($node.value, :$want);
    }

    multi method as_js(QAST::Stmts $node, :$want) {
        if self.is_ctxsave($node) {
            self.NYI("handle CTXSAVE");
        } else {
            self.compile_all_the_statements($node, $want);
        }
    }

    multi method as_js(QAST::VM $node, :$want) {
        # We ignore QAST::VM as we don't support a js specific one, and the ones nqp generate contain parrot specific stuff we don't care about.
        Chunk.new($T_VOID,'',[]);
    }

    multi method as_js(QAST::Op $node, :$want) {
        QAST::OperationsJS.compile_op(self, $node, :$want);
    }

    multi method as_js(QAST::CompUnit $node, :$want) {
        # Should have a single child which is the outer block.
        if +@($node) != 1 || !nqp::istype($node[0], QAST::Block) {
            nqp::die("QAST::CompUnit should have one child that is a QAST::Block");
        }

        # Compile the block.
        my $block_js := self.as_js($node[0], :want($T_VOID));

        if nqp::defined($node.main) {
            my $main_block := QAST::Block.new($node.main);

            my $main := self.as_js($main_block, :want($T_VOID));

            Chunk.new($T_VOID, "", [$block_js, $main, self.mangled_cuid($main_block) ~ "();\n"]);
            
        } else {
            $block_js;
        }
    }

    method declare_var(QAST::Var $node) {
        # TODO vars more complex the non-dynamic lexicals
        if $node.decl eq 'var' {
            $*BLOCK.add_js_lexical(self.mangle_name($node.name));
        } elsif $node.decl eq 'param' {
            if $node.scope eq 'local' || $node.scope eq 'lexical' {
                $*BLOCK.add_param($node);
            } else {
                nqp::die("Parameter cannot have scope '{$node.scope}'; use 'local' or 'lexical'");
            }
        }
    }

    multi method as_js(QAST::Var $node, :$want) {
        self.declare_var($node);
        self.compile_var($node);
    }
    
    method var_is_lexicalish(QAST::Var $var) {
        $var.scope eq 'lexical' || $var.scope eq 'typevar';
    }

    method as_js_clear_bindval($node, :$want) {
        my $*BINDVAL := 0;
        self.as_js($node, :$want);
    }

    method is_dynamic_var($var) {
        # TODO
        0;
    }

    method compile_var(QAST::Var $var) {
        if self.var_is_lexicalish($var) && self.is_dynamic_var($var) {
            self.TODO("dynamic variables");
        } elsif self.var_is_lexicalish($var) || $var.scope eq 'local' {
            my $type := $T_OBJ;
            my $mangled := self.mangle_name($var.name);
            if $*BINDVAL {
                # TODO better source mapping
                # TODO use the proper type 
                my $bindval := self.as_js_clear_bindval($*BINDVAL, :want($T_OBJ));
                Chunk.new($type,$mangled, [$bindval,'('~$mangled~' = ('~ $bindval.expr ~ "));\n"]);
            } else {
                # TODO get the proper type 
                Chunk.new($type, $mangled, [], :node($var));
            }
        } elsif ($var.scope eq 'positional') {
            # TODO work on things other than nqp lists
            # TODO think about nulls and missing elements
            if $*BINDVAL {
                my $array := self.as_js($var[0], :want($T_OBJ));
                my $index := self.as_js($var[1], :want($T_INT));
                my $bindval := self.as_js_clear_bindval($*BINDVAL, :want($T_OBJ));
                Chunk.new($T_OBJ, $bindval.expr, [$array, $index, $bindval, "({$array.expr}[{$index.expr}] = $bindval)"], :node($var));
            } else {
                my $array := self.as_js($var[0], :want($T_OBJ));
                my $index := self.as_js($var[1], :want($T_INT));
                Chunk.new($T_OBJ, "{$array.expr}[{$index.expr}]", [$array, $index], :node($var));
            }
        } else {
            self.NYI("Unimplemented QAST::Var scope: " ~ $var.scope);
        }
    }

    multi method as_js($unknown, :$want) {
        self.NYI("Unimplemented QAST node type: " ~ $unknown.HOW.name($unknown));
    }


    method as_js_with_prelude($ast) {
        Chunk.new($T_VOID,"",[
            "var nqp = require('nqp-runtime');\n",
            "\nvar top_ctx = nqp.top_context();\n",
            # temporary HACK
            "var ARGS = process.argv;\n",
            self.as_js($ast, :want($T_VOID))
        ]);
    }

    method emit($ast) {
       self.as_js_with_prelude($ast).join
    }

    # return a json datastructure we later process into a source map
    method emit_with_source_map($ast) {
       self.as_js_with_prelude($ast).with_source_map_info
    }
}
