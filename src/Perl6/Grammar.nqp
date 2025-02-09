use QRegex;
use NQPP6QRegex;
use NQPP5QRegex;
use Perl6::Actions;
use Perl6::World;
use Perl6::Pod;

role startstops[$start, $stop1, $stop2] {
    token starter { $start }
    token stopper { $stop1 | $stop2 }
}

role startstop[$start, $stop] {
    token starter { $start }
    token stopper { $stop }
}

role stop[$stop] {
    token starter { <!> }
    token stopper { $stop }
}

# This role captures things that STD factors out from any individual grammar,
# but that don't make sense to go in HLL::Grammar.
role STD {
    token opener {
        <[
        \x0028 \x003C \x005B \x007B \x00AB \x0F3A \x0F3C \x169B \x2018 \x201A \x201B
        \x201C \x201E \x201F \x2039 \x2045 \x207D \x208D \x2208 \x2209 \x220A \x2215
        \x223C \x2243 \x2252 \x2254 \x2264 \x2266 \x2268 \x226A \x226E \x2270 \x2272
        \x2274 \x2276 \x2278 \x227A \x227C \x227E \x2280 \x2282 \x2284 \x2286 \x2288
        \x228A \x228F \x2291 \x2298 \x22A2 \x22A6 \x22A8 \x22A9 \x22AB \x22B0 \x22B2
        \x22B4 \x22B6 \x22C9 \x22CB \x22D0 \x22D6 \x22D8 \x22DA \x22DC \x22DE \x22E0
        \x22E2 \x22E4 \x22E6 \x22E8 \x22EA \x22EC \x22F0 \x22F2 \x22F3 \x22F4 \x22F6
        \x22F7 \x2308 \x230A \x2329 \x23B4 \x2768 \x276A \x276C \x276E \x2770 \x2772
        \x2774 \x27C3 \x27C5 \x27D5 \x27DD \x27E2 \x27E4 \x27E6 \x27E8 \x27EA \x2983
        \x2985 \x2987 \x2989 \x298B \x298D \x298F \x2991 \x2993 \x2995 \x2997 \x29C0
        \x29C4 \x29CF \x29D1 \x29D4 \x29D8 \x29DA \x29F8 \x29FC \x2A2B \x2A2D \x2A34
        \x2A3C \x2A64 \x2A79 \x2A7D \x2A7F \x2A81 \x2A83 \x2A8B \x2A91 \x2A93 \x2A95
        \x2A97 \x2A99 \x2A9B \x2AA1 \x2AA6 \x2AA8 \x2AAA \x2AAC \x2AAF \x2AB3 \x2ABB
        \x2ABD \x2ABF \x2AC1 \x2AC3 \x2AC5 \x2ACD \x2ACF \x2AD1 \x2AD3 \x2AD5 \x2AEC
        \x2AF7 \x2AF9 \x2E02 \x2E04 \x2E09 \x2E0C \x2E1C \x2E20 \x3008 \x300A \x300C
        \x300E \x3010 \x3014 \x3016 \x3018 \x301A \x301D \xFD3E \xFE17 \xFE35 \xFE37
        \xFE39 \xFE3B \xFE3D \xFE3F \xFE41 \xFE43 \xFE47 \xFE59 \xFE5B \xFE5D \xFF08
        \xFF1C \xFF3B \xFF5B \xFF5F \xFF62
        ]>
    }

    method balanced($start, $stop) {
        if nqp::istype($stop, VMArray) {
            self.HOW.mixin(self, startstops.HOW.curry(startstops, $start, $stop[0], $stop[1]));
        }
        else {
            self.HOW.mixin(self, startstop.HOW.curry(startstop, $start, $stop));
        }
    }
    method unbalanced($stop) {
        self.HOW.mixin(self, stop.HOW.curry(stop, $stop));
    }

    token starter { <!> }
    token stopper { <!> }

    my %quote_lang_cache;
    method quote_lang($l, $start, $stop, @base_tweaks?, @extra_tweaks?) {
        sub lang_key() {
            my $stopstr := nqp::istype($stop,VMArray) ?? nqp::join(' ',$stop) !! $stop;
            my @keybits := [$l.HOW.name($l), $start, $stopstr];
            for @base_tweaks {
                @keybits.push($_);
            }
            for @extra_tweaks {
                if $_[0] eq 'to' {
                    return 'NOCACHE';
                }
                @keybits.push($_[0] ~ '=' ~ $_[1]);
            }
            nqp::join("\0", @keybits)
        }
        sub con_lang() {
            my $lang := $l.'!cursor_init'(self.orig(), :p(self.pos()), :shared(self.'!shared'()));
            for @base_tweaks {
                $lang := $lang."tweak_$_"(1);
            }

            for @extra_tweaks {
                my $t := $_[0];
                if nqp::can($lang, "tweak_$t") {
                    $lang := $lang."tweak_$t"($_[1]);
                }
                else {
                    self.sorry("Unrecognized adverb: :$t");
                }
            }
            nqp::istype($stop,VMArray) ||
            $start ne $stop ?? $lang.balanced($start, $stop)
                            !! $lang.unbalanced($stop);
        }

        # Get language from cache or derive it.
        my $key := lang_key();
        nqp::ifnull(%quote_lang_cache, %quote_lang_cache := nqp::hash());
        nqp::existskey(%quote_lang_cache, $key) && $key ne 'NOCACHE'
            ?? %quote_lang_cache{$key}
            !! (%quote_lang_cache{$key} := con_lang());
    }

    token babble($l, @base_tweaks?) {
        :my @extra_tweaks;

        [ <quotepair> <.ws>
            {
                my $kv := $<quotepair>[-1].ast;
                my $k  := $kv.named;
                if nqp::istype($kv, QAST::Stmts) || nqp::istype($kv, QAST::Stmt) && +@($kv) == 1 {
                    $kv := $kv[0];
                }
                my $v := nqp::istype($kv, QAST::IVal)
                    ?? $kv.value
                    !! $kv.has_compile_time_value
                        ?? $kv.compile_time_value
                        !! self.panic("Invalid adverb value for " ~ $<quotepair>[-1].Str);
                nqp::push(@extra_tweaks, [$k, $v]);
            }
        ]*

        $<B>=[<?before .>]
        {
            # Work out the delimeters.
            my $c := $/.CURSOR;
            my @delims := $c.peek_delimiters($c.target, $c.pos);
            my $start := @delims[0];
            my $stop  := @delims[1];

            # Get the language.
            my $lang := self.quote_lang($l, $start, $stop, @base_tweaks, @extra_tweaks);
            $<B>.'!make'([$lang, $start, $stop]);
        }
    }

    my @herestub_queue;

    my class Herestub {
        has $!delim;
        has $!orignode;
        has $!lang;
        method delim() { $!delim }
        method orignode() { $!orignode }
        method lang() { $!lang }
    }

    role herestop {
        token starter { <!> }
        token stopper { ^^ {} $<ws>=(\h*) $*DELIM \h* $$ [\r\n | \v]? }
        method parsing_heredoc() { 1 }
    }

    method heredoc () {
        if @herestub_queue {
            my $here := self.'!cursor_start_cur'();
            $here.'!cursor_pos'(self.pos);
            while @herestub_queue {
                my $herestub := nqp::shift(@herestub_queue);
                my $*DELIM := $herestub.delim;
                my $lang := $herestub.lang.HOW.mixin($herestub.lang, herestop);
                my $doc := $here.nibble($lang);
                if $doc {
                    # Match stopper.
                    my $stop := $lang.'!cursor_init'(self.orig(), :p($doc.pos), :shared(self.'!shared'())).stopper();
                    unless $stop {
                        self.panic("Ending delimiter $*DELIM not found");
                    }
                    $here.'!cursor_pos'($stop.pos);

                    # Get it trimmed and AST updated.
                    $*ACTIONS.trim_heredoc($doc, $stop, $herestub.orignode.MATCH.ast);
                }
                else {
                    self.panic("Ending delimiter $*DELIM not found");
                }
            }
            $here.'!cursor_pass'($here.pos);
            $here
        }
        else {
            self
        }
    }

    token cheat_heredoc {
        <?{ +@herestub_queue }> \h* <[ ; } ]> \h* <?before \n | '#'> <.ws> <?MARKER('endstmt')>
    }

    method queue_heredoc($delim, $lang) {
        nqp::ifnull(@herestub_queue, @herestub_queue := []);
        nqp::push(@herestub_queue, Herestub.new(:$delim, :$lang, :orignode(self)));
        return self;
    }

    token quibble($l, *@base_tweaks) {
        :my $lang;
        :my $start;
        :my $stop;
        <babble($l, @base_tweaks)>
        { my $B := $<babble><B>.ast; $lang := $B[0]; $start := $B[1]; $stop := $B[2]; }

        $start <nibble($lang)> [ $stop || { $/.CURSOR.typed_panic('X::Comp::AdHoc', payload => "Couldn't find terminator $stop (corresponding $start was at line {HLL::Compiler.lineof($<babble><B>.orig(), $<babble><B>.from())})", expected => [$stop] ) } ]

        {
            nqp::can($lang, 'herelang') && self.queue_heredoc(
                $*W.nibble_to_str($/, $<nibble>.ast[1], -> { "Stopper '" ~ $<nibble> ~ "' too complex for heredoc" }),
                $lang.herelang)
        }
    }

    method nibble($lang) {
        my $lang_cursor := $lang.'!cursor_init'(self.orig(), :p(self.pos()), :shared(self.'!shared'()));
        my $*ACTIONS;
        for %*LANG {
            if nqp::istype($lang, $_.value) {
                $*ACTIONS := %*LANG{$_.key ~ '-actions'};
                last;
            }
        }
        $lang_cursor.nibbler();
    }

    token obsbrace { <.obs('curlies around escape argument','square brackets')> }

    method panic(*@args) {
        self.typed_panic('X::Comp::AdHoc', payload => nqp::join('', @args))
    }
    method sorry(*@args) {
        self.typed_sorry('X::Comp::AdHoc', payload => nqp::join('', @args))
    }
    method worry(*@args) {
        self.typed_worry('X::Comp::AdHoc', payload => nqp::join('', @args))
    }

    method typed_panic($type_str, *%opts) {
        $*W.throw(self.MATCH(), nqp::split('::', $type_str), |%opts);
    }
    method typed_sorry($type_str, *%opts) {
        if +@*SORROWS + 1 == $*SORRY_LIMIT {
            $*W.throw(self.MATCH(), nqp::split('::', $type_str), |%opts);
        }
        else {
            @*SORROWS.push($*W.typed_exception(self.MATCH(), nqp::split('::', $type_str), |%opts));
        }
        self
    }
    method typed_worry($type_str, *%opts) {
        unless %*PRAGMAS<no-worries> {
            %*PRAGMAS<fatal>
              ?? self.typed_sorry($type_str, |%opts)
              !! @*WORRIES.push($*W.typed_exception(
                   self.MATCH(), nqp::split('::', $type_str), |%opts));
        }
        self
    }

    method malformed($what) {
        self.typed_panic('X::Syntax::Malformed', :$what);
    }
    method missing_block() {
        if $*BORG<block> {
            my $pos := self.pos;
            self.'!clear_highwater'();
            self.'!cursor_pos'($*BORG<block>.CURSOR.pos);
            self.typed_sorry('X::Syntax::BlockGobbled', what => ($*BORG<name> // ''));
            self.'!cursor_pos'($pos);
            self.missing("block (apparently claimed by " ~ ($*BORG<name> ?? "'" ~ $*BORG<name> ~ "'" !! "expression") ~ ")");
        } elsif %*MYSTERY {
            self.missing("block (taken by some undeclared routine?)");
        } else {
            self.missing("block");
        }
    }
    method missing($what) {
        self.typed_panic('X::Syntax::Missing', :$what);
    }
    method NYI($feature) {
        self.typed_panic('X::Comp::NYI', :$feature)
    }

    token experimental($feature) {
        <?{ try $*W.find_symbol(['EXPERIMENTAL-' ~ nqp::uc($feature)]) }>
        || <.typed_panic('X::Experimental', :$feature)>
    }

    method EXPR_nonassoc($cur, $left, $right) {
        self.typed_panic('X::Syntax::NonAssociative', :left(~$left), :right(~$right));
    }

    # "when" arg assumes more things will become obsolete after Perl 6 comes out...
    method obs($old, $new, $when = 'in Perl 6') {
        $*W.throw(self.MATCH(), ['X', 'Obsolete'],
            old         => $old,
            replacement => $new,
            when        => $when,
        );
    }
    method obsvar($name) {
        $*W.throw(self.MATCH(), ['X', 'Syntax', 'Perl5Var'], :$name);
    }
    method sorryobs($old, $new, $when = 'in Perl 6') {
        $*W.throw(self.MATCH(), ['X', 'Obsolete'],
            old         => $old,
            replacement => $new,
            when        => $when,
        );
    }
    method worryobs($old, $new, $when = 'in Perl 6') {
        self.typed_worry('X::Obsolete',
            old         => $old,
            replacement => $new,
            when        => $when,
        );
    }

    method dupprefix($prefixes) {
        self.typed_panic('X::Syntax::DuplicatedPrefix', :$prefixes);
    }

    method mark_variable_used($name) {
        my $lex := $*W.cur_lexpad();
        my %sym := $lex.symbol($name);
        if %sym {
            %sym<used> := 1;
        }
        else {
            # Add mention-only record (used to poison outer
            # usages and disambiguate hashes/blocks by use of
            # $_ when $*IMPLICIT is in force).
            my $au := $lex.ann('also_uses');
            $lex.annotate('also_uses', $au := {}) unless $au;
            $au{$name} := 1;
        }
    }

    method check_variable($var) {
        my $varast := $var.ast;
        if nqp::istype($varast, QAST::Op) && $varast.op eq 'ifnull' {
            $varast := $varast[0];
        }
        if !$*IN_DECL && nqp::istype($varast, QAST::Var) && $varast.scope eq 'lexical' {
            my $name := $varast.name;

            if $name ne '%_' && $name ne '@_' && !$*W.is_lexical($name) {
                my $sigil := $var<sigil> || nqp::substr($name,0,1);
                if $sigil ne '&' {
                    if !$*STRICT {
                        $*W.auto_declare_var($var);
                    }
                    else {
                        my @suggestions := $*W.suggest_lexicals($name);

                        if nqp::can($*PACKAGE.HOW, 'get_attribute_for_usage') {
                            my $sigil    := nqp::substr($name, 0, 1);
                            my $twigil   := nqp::concat($sigil, '!');
                            my $basename := nqp::substr($name, 1, nqp::chars($name) - 1);
                            my $attrname := nqp::concat($twigil, $basename);

                            my $attribute := $*PACKAGE.HOW.get_attribute_for_usage($*PACKAGE, $attrname);
                            nqp::push(@suggestions, $attrname);

                            CATCH {}
                        }
                        $*W.throw($var, ['X', 'Undeclared'], symbol => $name, suggestions => @suggestions, precursor => '1');
                    }
                }
                else {
                    $var.CURSOR.add_mystery($name, $var.to, 'var');
                }
            }
            else {
                self.mark_variable_used($name);
            }
        }
        if !$*IN_DECL && nqp::istype($varast, QAST::Op) && $varast.name eq '&DYNAMIC' {
            my $lex := $*W.cur_lexpad();
            if nqp::istype($varast[0], QAST::Want) && nqp::istype($varast[0][2], QAST::SVal) {
                my $au := $lex.ann('also_uses');
                $lex.annotate('also_uses', $au := {}) unless $au;
                $au{$varast[0][2].value} := 1;
            }
        }
        self
    }

    token RESTRICTED {
        [ <?{ $*RESTRICTED }> [ $ || <.malformed($*RESTRICTED)> ] ]?
        <!>
    }
}

grammar Perl6::Grammar is HLL::Grammar does STD {
    my $sc_id := 0;
    method TOP() {
        # Language braid.
        my %*LANG;
        %*LANG<Regex>           := Perl6::RegexGrammar;
        %*LANG<Regex-actions>   := Perl6::RegexActions;
        %*LANG<P5Regex>         := Perl6::P5RegexGrammar;
        %*LANG<P5Regex-actions> := Perl6::P5RegexActions;
        %*LANG<Quote>           := Perl6::QGrammar;
        %*LANG<Quote-actions>   := Perl6::QActions;
        %*LANG<MAIN>            := Perl6::Grammar;
        %*LANG<MAIN-actions>    := Perl6::Actions;

        # Package declarator to meta-package mapping. Starts pretty much empty;
        # we get the mappings either imported or supplied by the setting. One
        # issue is that we may have no setting to provide them, e.g. when we
        # compile the setting, but it still wants some kinda package. We just
        # fudge in knowhow for that.
        my %*HOW;
        my %*HOWUSE;
        %*HOW<knowhow> := nqp::knowhow();
        %*HOW<package> := nqp::knowhow();

        # Will we use the result of this? (Yes for EVAL and REPL).
        my $*NEED_RESULT := nqp::existskey(%*COMPILING<%?OPTIONS>, 'outer_ctx');

        # Symbol table and serialization context builder - keeps track of
        # objects that cross the compile-time/run-time boundary that are
        # associated with this compilation unit.
        my $file := nqp::getlexdyn('$?FILES');
        my $source_id := nqp::sha1(
            nqp::defined(%*COMPILING<%?OPTIONS><outer_ctx>)
                ?? self.target() ~ $sc_id++
                !! self.target());
        my $*W := nqp::isnull($file) ??
            Perl6::World.new(:handle($source_id)) !!
            Perl6::World.new(:handle($source_id), :description($file));
        $*W.add_initializations();

        my $cursor := self.comp_unit;
        $*W.pop_lexpad(); # UNIT
        $*W.pop_lexpad(); # UNIT_OUTER
        $cursor;
    }

    ## Lexer stuff

    token apostrophe {
        <[ ' \- ]>
    }

    token identifier {
        <.ident> [ <.apostrophe> <.ident> ]*
    }

    token name {
        [
        | <identifier> <morename>*
        | <morename>+
        ]
    }

    token morename {
        :my $*QSIGIL := '';
        '::'
        [
        ||  <?before '(' | <alpha> >
            [
            | <identifier>
            | :dba('indirect name') '(' ~ ')' [ <.ws> <EXPR> ]
            ]
        || <?before '::'> <.typed_panic: "X::Syntax::Name::Null">
        || $<bad>=[<.sigil><.identifier>] { my $b := $<bad>; self.malformed("lookup of ::$b; please use ::('$b'), ::\{'$b'\}, or ::<$b>") }
        ]?
    }

    token longname {
        <name> {} [ <?before ':' <+alpha+[\< \[ \« ]>> <!RESTRICTED> <colonpair> ]*
    }

    token deflongname {
        :dba('new name to be defined')
        <name> <colonpair>*
    }

    token subshortname {
        <desigilname>
    }

    token sublongname {
        <subshortname> <sigterm>?
    }

    token deftermnow { <defterm> }

    token defterm {     # XXX this is probably too general
        :dba('new term to be defined')
        <identifier>
        [
        | <colonpair>+
            {
                if $<colonpair>[0]<coloncircumfix> -> $cf {
                    my $category := $<identifier>.Str;
                    my $opname := $cf<circumfix>
                        ?? $*W.colonpair_nibble_to_str($/, $cf<circumfix><nibble>)
                        !! '';
                    my $canname  := $category ~ $*W.canonicalize_pair('sym', $opname);
                    my $termname := $category ~ $*W.canonicalize_pair('', $opname);
                    $/.CURSOR.add_categorical($category, $opname, $canname, $termname, :defterm);
                }
            }
        | <?>
        ]
    }

    token module_name {
        <longname>
        [ <?[[]> :dba('generic role') '[' ~ ']' <arglist> ]?
    }

    token end_keyword {
        » <!before <[ \( \\ ' \- ]> || \h* '=>'>
    }
    token end_prefix {
        <.end_keyword> \s*
    }
    token spacey { <?[\s#]> }

    token kok {
        <.end_keyword>
        [
        || <?before <[ \s \# ]> > <.ws>
        || <?{
                my $n := nqp::substr(self.orig, self.from, self.pos - self.from);
                $*W.is_name([$n]) || $*W.is_name(['&' ~ $n])
                    ?? False
                    !! self.sorry("Whitespace required after keyword '$n'")
           }>
        ]
    }

    token tok {
        <.end_keyword>
        <!{
                my $n := nqp::substr(self.orig, self.from, self.pos - self.from);
                $*W.is_name([$n]) || $*W.is_name(['&' ~ $n])
        }>
    }


    token ENDSTMT {
        [
        | \h* $$ <.ws> <?MARKER('endstmt')>
        | <.unv>? $$ <.ws> <?MARKER('endstmt')>
        ]?
    }

    # ws is highly performance sensitive. So, we check if we already marked it
    # at this point with a simple method, and only if that is not the case do
    # we bother doing any pattern matching.
    method ws() {
        if self.MARKED('ws') {
            self
        }
        else {
            self._ws()
        }
    }
    token _ws {
        :my $old_highexpect := self.'!fresh_highexpect'();
        :dba('whitespace')
        <!ww>
        [
        | [\r\n || \v] <.heredoc>
        | <.unv>
        | <.unsp>
        ]*
        <?MARKER('ws')>
        :my $stub := self.'!fresh_highexpect'();
    }

    token unsp {
        \\ <?before \s | '#'>
        :dba('unspace')
        [
        | <.vws>
        | <.unv>
        | <.unsp>
        ]*
    }

    token vws {
        :dba('vertical whitespace')
        [
            [
            | \v
            | '<<<<<<<' {} <?before [.*? \v '=======']: .*? \v '>>>>>>>' > <.sorry: 'Found a version control conflict marker'> \V* \v
            | '=======' {} .*? \v '>>>>>>>' \V* \v   # ignore second half
            ]
        ]+
    }

    token unv {
        :dba('horizontal whitespace')
        [
        | \h+
        | \h* <.comment>
        | <?before \h* '=' [ \w | '\\'] > ^^ <.pod_content_toplevel>
        ]
    }

    proto token comment { <...> }

    token comment:sym<#> {
       '#' {} \N*
    }

    token comment:sym<#`(...)> {
        '#`' <?opener> {}
        [ <.quibble(%*LANG<Quote>)> || <.typed_panic: 'X::Syntax::Comment::Embedded'> ]
    }

    token comment:sym<#|(...)> {
        '#|' <?opener> <attachment=.quibble(%*LANG<Quote>)>
        {
            unless $*POD_BLOCKS_SEEN{ self.from() } {
                $*POD_BLOCKS_SEEN{ self.from() } := 1;
                if $*DECLARATOR_DOCS eq '' {
                    $*DECLARATOR_DOCS := $<attachment><nibble>;
                } else {
                    $*DECLARATOR_DOCS := nqp::concat($*DECLARATOR_DOCS, nqp::concat("\n", $<attachment><nibble>));
                }
            }
        }
    }

    token comment:sym<#|> {
        '#|' \h+ $<attachment>=[\N*]
        {
            unless $*POD_BLOCKS_SEEN{ self.from() } {
                $*POD_BLOCKS_SEEN{ self.from() } := 1;
                if $*DECLARATOR_DOCS eq '' {
                    $*DECLARATOR_DOCS := $<attachment>;
                } else {
                    $*DECLARATOR_DOCS := nqp::concat($*DECLARATOR_DOCS, nqp::concat("\n", $<attachment>));
                }
            }
        }
    }

    token comment:sym<#=(...)> {
        '#=' <?opener> <attachment=.quibble(%*LANG<Quote>)>
        {
            self.attach_trailing_docs(~$<attachment><nibble>);
        }
    }

    token comment:sym<#=> {
        '#=' \h+ $<attachment>=[\N*]
        {
            self.attach_trailing_docs(~$<attachment>);
        }
    }

    method attach_leading_docs() {
        if ~$*DOC ne '' {
            my $cont  := Perl6::Pod::serialize_aos(
                [Perl6::Pod::formatted_text(~$*DOC)]
            ).compile_time_value;
            my $block := $*W.add_constant(
                'Pod::Block::Declarator', 'type_new',
                :nocache, :leading([$cont]),
            );
            $*POD_BLOCK := $block.compile_time_value;
            $*POD_BLOCKS.push($*POD_BLOCK);
        }
        self
    }

    method attach_trailing_docs($doc) {
        unless $*POD_BLOCKS_SEEN{ self.from() } {
            $*POD_BLOCKS_SEEN{ self.from() } := 1;
            my $pod_block;
            if $doc ne '' {
                my $cont  := Perl6::Pod::serialize_aos(
                    [Perl6::Pod::formatted_text($doc)]
                ).compile_time_value;
                my $block := $*W.add_constant(
                    'Pod::Block::Declarator', 'type_new',
                    :nocache, :trailing([$cont]),
                );
                $pod_block := $block.compile_time_value;
            }
            unless $*PRECEDING_DECL =:= Mu {
                Perl6::Pod::document($/, $*PRECEDING_DECL, $pod_block, :trailing);
            }
        }
    }

    token pod_content_toplevel {
        <pod_block>
    }

    proto token pod_content { <...> }

    token pod_content:sym<block> {
        <pod_newline>*
        <pod_block>
        <pod_newline>*
    }

    # any number of paragraphs of text
    token pod_content:sym<text> {
        <pod_newline>*
        <pod_textcontent>+ % <pod_newline>+
        <pod_newline>*
    }

    # not a block, just a directive
    token pod_content:sym<config> {
        <pod_newline>*
        ^^ \h* '=config' \h+ $<type>=\S+ <pod_configuration>
        <pod_newline>+
    }

    proto token pod_textcontent { <...> }

    # text not being code
    token pod_textcontent:sym<regular> {
        $<spaces>=[ \h* ]
         <?{ $*POD_IN_CODE_BLOCK
             || !$*ALLOW_INLINE_CODE
             || ($<spaces>.to - $<spaces>.from) <= $*VMARGIN }>

        $<text> = [
            \h* <!before '=' \w> <pod_string> [ <pod_newline> | $ ]
        ] +
    }

    token pod_textcontent:sym<code> {
        $<spaces>=[ \h* ]
        <?{ !$*POD_IN_CODE_BLOCK
            && $*ALLOW_INLINE_CODE
            && ($<spaces>.to - $<spaces>.from) > $*VMARGIN }>
        $<text> = [
            [<!before '=' \w> \N+]+ % [<pod_newline>+ $<spaces>]
        ]
    }

    token pod_formatting_code {
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        :my $*POD_IN_FORMATTINGCODE := nqp::getlexdyn('$*POD_IN_FORMATTINGCODE');
        :my $*POD_ANGLE_COUNT := nqp::getlexdyn('$*POD_ANGLE_COUNT');
        <?{ $*POD_ALLOW_FCODES }>

        :my $endtag;
        <code=[A..Z]>
        $<begin-tag>=['<'+ <![<]> | '«'] { $*POD_IN_FORMATTINGCODE := 1 }
        <?{
            my $codenum := nqp::ord($<code>.Str) - nqp::ord("A");
            if !($*POD_ALLOW_FCODES +& (2 ** $codenum)) {
                0
            } elsif ~$<begin-tag> eq '«' {
              $endtag := "»";
              $*POD_ANGLE_COUNT := -1;
              1
            } else {
              my int $ct := nqp::chars($<begin-tag>);
              $endtag := nqp::x(">", $ct);
              my $rv := $*POD_ANGLE_COUNT <= 0 || $*POD_ANGLE_COUNT >= $ct;
              $*POD_ANGLE_COUNT := $ct;
              $rv;
            }
        }>
        {
            if $<code>.Str eq "V" || $<code>.Str eq "C" {
                $*POD_ALLOW_FCODES := 0;
            }
        }
        [ <!{$<code> eq 'E'}>
          $<contents>=[
              <!before $endtag>
              [ <?{$<code> ne 'L' && $<code> ne 'D' && $<code> ne 'X' }> || <!before \s* \| > ]
              <pod_string_character>
          ]*
        ]?
        [
        | <?{$<code> eq 'L'}> \s* \| \s* $<meta>=[<!before $endtag>.]+
        | <?{$<code> eq 'X'}> \s* \| \s* ( [$<meta>=[<!before $endtag | <[,;]> >.]+] +%% \, ) +%% \;
        | <?{$<code> eq 'D'}> \s* \| \s* [$<meta>=[<!before $endtag | \; >.]+] +%% \;
        | <?{$<code> eq 'E'}> ( <integer> | $<uni_name>=<[A..Z\s]>+ <![a..z]> || $<html_ref>=<[A..Za..z]>+ ) +%% \;
        ]?
        [ $endtag || <.worry: "Pod formatting code $<code> missing endtag '$endtag'."> ]
    }

    token pod_balanced_braces {
        <?{ $*POD_IN_FORMATTINGCODE }>
        :my $endtag;
        [
            $<braces>=[
                      || '<'+ <![<]>
                      || '>'+ <![>]>
                      ]
            <?{ nqp::chars($<braces>) < $*POD_ANGLE_COUNT || $*POD_ANGLE_COUNT < 0 }>
          ||
            <?{ $*POD_ANGLE_COUNT >= 1 }>
            $<start>=['<'+] <![<]>
            <?{ nqp::chars($<start>) == $*POD_ANGLE_COUNT || $*POD_ANGLE_COUNT < 0 }>
            {
                $endtag := nqp::x(">", nqp::chars($<start>));
            }
            $<contents>=[ <pod_string_character>*?]
            <!after '>'> $<endtag>=[$endtag]
        ]
    }

    token pod_string {
        <pod_string_character>+
    }

    token pod_string_character {
        <pod_balanced_braces> || <pod_formatting_code> || $<char>=[ \N || [
            <?{ $*POD_IN_FORMATTINGCODE }> \n [
                <?{ $*POD_DELIMITED_CODE_BLOCK }> <!before \h* '=end' \h+ code> ||
                <!before \h* '=' \w>
                ]
            ]
        ]
    }

    proto token pod_block { <...> }

    token pod_configuration($spaces = '') {
        [ [\n $spaces '=']? \h+ <colonpair> ]*
    }

    token pod_block:sym<delimited_comment> {
        ^^
        $<spaces> = [ \h* ]
        '=begin' \h+ 'comment' {}
        <pod_configuration($<spaces>)> <pod_newline>+
        [
         $<pod_content> = [ .*? ]
         ^^ $<spaces> '=end' \h+
         [
            'comment' [ <pod_newline> | $ ]
            || $<instead>=<identifier>? {$/.CURSOR.typed_panic: 'X::Syntax::Pod::BeginWithoutEnd', type => 'comment', spaces => ~$<spaces>, instead => $<instead> ?? ~$<instead> !! ''}
         ]
        ]
    }

    token pod_block:sym<delimited> {
        ^^
        $<spaces> = [ \h* ]
        '=begin'
        [ <?pod_newline>
          <.typed_panic('X::Syntax::Pod::BeginWithoutIdentifier')>
        ]?
        \h+ <!before 'finish'>
        {
            $*VMARGIN    := $<spaces>.to - $<spaces>.from;
        }
        :my $*ALLOW_INLINE_CODE := 0;
        $<type> = [
            <pod_code_parent> { $*ALLOW_INLINE_CODE := 1 }
            || <identifier>
        ]
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_configuration($<spaces>)> <pod_newline>+
        [
         <pod_content> *
         ^^ $<spaces> '=end' \h+
         [
             $<type> [ <pod_newline> | $ ]
             || $<instead>=<identifier>? {$/.CURSOR.typed_panic: 'X::Syntax::Pod::BeginWithoutEnd', type => ~$<type>, spaces => ~$<spaces>, instead => $<instead> ?? ~$<instead> !! ''}
         ]
        ]
    }


    token pod_block:sym<delimited_table> {
        ^^
        $<spaces> = [ \h* ]
        '=begin' \h+ 'table' {}
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_configuration($<spaces>)> <pod_newline>+
        [
         [ $<table_row>=<.table_row_or_blank> ]*
         ^^ \h* '=end' \h+
         [
            'table' [ <pod_newline> | $ ]
             || $<instead>=<identifier>? {$/.CURSOR.typed_panic: 'X::Syntax::Pod::BeginWithoutEnd', type => 'table', spaces => ~$<spaces>, instead => $<instead> ?? ~$<instead> !! ''}
         ]
        ]
    }

    token pod_block:sym<delimited_code> {
        ^^
        $<spaces> = [ \h* ]
        '=begin' \h+ 'code' {}
        :my $*POD_ALLOW_FCODES  := 0;
        :my $*POD_IN_CODE_BLOCK := 1;
        :my $*POD_DELIMITED_CODE_BLOCK := 1;
        <pod_configuration($<spaces>)> <pod_newline>+
        [
        || <delimited_code_content($<spaces>)> $<spaces> '=end' \h+
            [ 'code' [ <pod_newline> | $ ]
              || $<instead>=<identifier>? {$/.CURSOR.typed_panic: 'X::Syntax::Pod::BeginWithoutEnd', type => 'code', spaces => ~$<spaces>, instead => $<instead> ?? ~$<instead> !! ''}
            ]
        ]
    }

    token delimited_code_content($spaces = '') {
        ^^
        (
        | $spaces
            <!before '=end' \h+ 'code' [ <pod_newline> | $ ]>
            <pod_string>**0..1 <pod_newline>
        | <pod_newline>
        )*
    }

    token table_row {
        \h* <!before '=' \w> \N+ [ \n | $ ]
    }

    token table_row_or_blank {
        <.table_row> | [\h* <!before '=' \w> \n ]
    }

    token pod_block:sym<finish> {
        ^^ \h*
        [
            | '=begin' \h+ 'finish' <pod_newline>
            | '=for'   \h+ 'finish' <pod_newline>
            | '=finish' <pod_newline>
        ]
        $<finish> = .*
    }

    token pod_block:sym<paragraph> {
        ^^
        $<spaces> = [ \h* ]
        '=for' \h+ <!before 'finish'>
        {
            $*VMARGIN := $<spaces>.to - $<spaces>.from;
        }
        :my $*ALLOW_INLINE_CODE := 0;
        $<type> = [
            <pod_code_parent> { $*ALLOW_INLINE_CODE := 1 }
            || <identifier>
        ]
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_configuration($<spaces>)> <pod_newline>
        <pod_content=.pod_textcontent>**0..1
    }

    token pod_block:sym<paragraph_comment> {
        ^^
        $<spaces> = [ \h* ]
        '=for' \h+ 'comment' {}
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_configuration($<spaces>)> <pod_newline>
        $<pod_content> = [ \h* <!before '=' \w> \N+ [ \n | $ ] ]*
    }

    token pod_block:sym<paragraph_table> {
        ^^
        $<spaces> = [ \h* ]
        '=for' \h+ 'table' {}
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_configuration($<spaces>)> <pod_newline>
        [ <!before \h* \n> <table_row>]*
    }

    token pod_block:sym<paragraph_code> {
        ^^
        $<spaces> = [ \h* ]
        '=for' \h+ 'code' {}
        :my $*POD_ALLOW_FCODES := 0;
        :my $*POD_IN_CODE_BLOCK := 1;
        <pod_configuration($<spaces>)> <pod_newline>
        [ <!before \h* '=' \w> <pod_line> ]*
    }

    token pod_block:sym<abbreviated> {
        ^^
        $<spaces> = [ \h* ]
        '=' <!before begin || end || for || finish || config>
        {
            $*VMARGIN := $<spaces>.to - $<spaces>.from;
        }
        :my $*ALLOW_INLINE_CODE := 0;
        $<type> = [
            <pod_code_parent> { $*ALLOW_INLINE_CODE := 1 }
            || <identifier>
        ]
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        [\h*\n|\h+]
        <pod_content=.pod_textcontent>**0..1
    }

    token pod_block:sym<abbreviated_comment> {
        ^^
        $<spaces> = [ \h* ]
        '=comment' {}
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        [\h*\n|\h+]
        $<pod_content> = [ \h* <!before '=' \w> \N+ [ \n | $ ] ]*
    }

    token pod_block:sym<abbreviated_table> {
        ^^
        $<spaces> = [ \h* ]
        '=table' {}
        :my $*POD_ALLOW_FCODES := nqp::getlexdyn('$*POD_ALLOW_FCODES');
        <pod_newline>
        [ <!before \h* \n> <table_row>]*
    }

    token pod_block:sym<abbreviated_code> {
        ^^
        $<spaces> = [ \h* ]
        '=code' {}
        :my $*POD_ALLOW_FCODES  := 0;
        :my $*POD_IN_CODE_BLOCK := 1;
        [\h*\n|\h+]
        [ <!before \h* '=' \w> <pod_line> ]*
    }

    token pod_line { <pod_string>**1 [ <pod_newline> | $ ] }

    token pod_newline {
        \h* \n
    }

    token pod_code_parent {
        [
        | [ 'pod' | 'item' \d* | 'nested' | 'defn' | 'finish' ]
        | <upper>+
        ]
        <![\w]>
    }

    token install_doc_phaser { <?> }

    token vnum {
        \w+ | '*'
    }

    token version {
        <?before v\d+\w*> 'v' $<vstr>=[<vnum>+ % '.' '+'?]
        <!before '-'|\'> # cheat because of LTM fail
    }

    ## Top-level rules

    token comp_unit {
        # From STD.pm.
        :my $*LEFTSIGIL;                           # sigil of LHS for item vs list assignment
        :my $*SCOPE := '';                         # which scope declarator we're under
        :my $*MULTINESS := '';                     # which multi declarator we're under
        :my $*QSIGIL := '';                        # sigil of current interpolation
        :my $*IN_META := '';                       # parsing a metaoperator like [..]
        :my $*IN_REDUCE := 0;                      # attempting to parse an [op] construct
        :my $*IN_DECL;                             # what declaration we're in
        :my $*IN_RETURN := 0;                      # are we in a return?
        :my $*HAS_SELF := '';                      # is 'self' available? (for $.foo style calls)
        :my $*begin_compunit := 1;                 # whether we're at start of a compilation unit
        :my $*DECLARAND;                           # the current thingy we're declaring, and subject of traits
        :my $*CODE_OBJECT;                         # the code object we're currently inside
        :my $*METHODTYPE;                          # the current type of method we're in, if any
        :my $*PKGDECL;                             # what type of package we're in, if any
        :my %*MYSTERY;                             # names we assume may be post-declared functions
        :my $*BORG := {};                          # who gets blamed for a missing block
        :my $*CCSTATE := '';
        :my $*STRICT;
        :my $*INVOCANT_OK := 0;
        :my $*INVOCANT;
        :my $*ARG_FLAT_OK := 0;

        # Error related. There are three levels: worry (just a warning), sorry
        # (fatal but not immediately so) and panic (immediately deadly). There
        # is a limit on the number of sorrows also. Unlike STD, which emits the
        # textual messages as it goes, we keep track of the exception objects
        # and, if needed, make a compositite exception group.
        :my @*WORRIES;                             # exception objects resulting from worry
        :my @*SORROWS;                             # exception objects resulting from sorry
        :my $*SORRY_LIMIT := 10;                   # when sorrow turns to panic

        # Extras.
        :my %*PRAGMAS;                             # compiler-handled lexical pragmas in effect
        :my @*NQP_VIOLATIONS;                      # nqp::ops per line number
        :my %*HANDLERS;                            # block exception handlers
        :my $*IMPLICIT;                            # whether we allow an implicit param
        :my $*HAS_YOU_ARE_HERE := 0;               # whether {YOU_ARE_HERE} has shown up
        :my $*OFTYPE;
        :my $*VMARGIN    := 0;                     # pod stuff
        :my $*ALLOW_INLINE_CODE := 0;              # pod stuff
        :my $*POD_IN_CODE_BLOCK := 0;              # pod stuff
        :my $*POD_IN_FORMATTINGCODE := 0;          # pod stuff
        :my $*POD_ALLOW_FCODES := 0b11111111111111111111111111; # allow which fcodes?
        :my $*POD_ANGLE_COUNT := 0;                # pod stuff
        :my $*IN_REGEX_ASSERTION := 0;
        :my $*IN_PROTO := 0;                       # are we inside a proto?
        :my $*NEXT_STATEMENT_ID := 1;              # to give each statement an ID
        :my $*IN_STMT_MOD := 0;                    # are we inside a statement modifier?
        :my $*COMPILING_CORE_SETTING := 0;         # are we compiling CORE.setting?

        # Various interesting scopes we'd like to keep to hand.
        :my $*GLOBALish;
        :my $*PACKAGE;
        :my $*UNIT;
        :my $*UNIT_OUTER;
        :my $*EXPORT;
        # stack of packages, which the 'is export' needs
        :my @*PACKAGES := [];

        # A place for Pod
        :my $*POD_BLOCKS := [];
        :my $*POD_BLOCKS_SEEN := {};
        :my $*POD_PAST;
        :my $*DECLARATOR_DOCS;
        :my $*PRECEDING_DECL; # for #= comments
        :my $*PRECEDING_DECL_LINE := -1; # XXX update this when I see another comment like it?

        # Quasis and unquotes
        :my $*IN_QUASI := 0;                       # whether we're currently in a quasi block
        :my $*MAIN := 'MAIN';

        # performance improvement stuff
        :my $*FAKE_INFIX_FOUND := 0;

        # for runaway detection
        :my $*LASTQUOTE := [0,0];

        { $*W.loading_and_symbol_setup($/) }

        <.finishpad>
        <.bom>?
        <statementlist=.FOREIGN_LANG($*MAIN, 'statementlist', 1)>

        <.install_doc_phaser>

        [ $ || <.typed_panic: 'X::Syntax::Confused'> ]

        <.explain_mystery>
        <.cry_sorrows>

        { $*W.mop_up_and_check($/) }
    }

    rule statementlist($*statement_level = 0) {
        :my %*LANG   := self.shallow_copy(nqp::getlexdyn('%*LANG'));
        :my %*HOW    := self.shallow_copy(nqp::getlexdyn('%*HOW'));
        :my %*HOWUSE := nqp::hash();
        :my $*STRICT := nqp::getlexdyn('$*STRICT');
        :dba('statement list')
        ''
        [
        | $
        | <?before <[\)\]\}]>>
        | [ <statement> <.eat_terminator> ]*
        ]
    }

    method shallow_copy(%hash) {
        my %result;
        for %hash {
            %result{$_.key} := $_.value;
        }
        %result
    }

    rule semilist {
        :dba('list composer')
        ''
        [
        | <?before <[)\]}]> >
        | [<statement><.eat_terminator> ]*
        ]
    }

    rule sequence {
        :dba('sequence of statements')
        ''
        [
        | <?before <[)\]}]> >
        | [<statement><.eat_terminator> ]*
        ]
    }

    token label {
        <identifier> ':' <?[\s]> <.ws>
        {
            $*LABEL := ~$<identifier>;
            if $*W.already_declared('my', $*PACKAGE, $*W.cur_lexpad(), [$*LABEL]) {
                $*W.throw($/, ['X', 'Redeclaration'], symbol => $*LABEL);
            }
            my str $orig      := self.orig();
            my int $total     := nqp::chars($orig);
            my int $from      := self.MATCH.from();
            my int $to        := self.MATCH.to() + nqp::chars($*LABEL);
            my int $line      := HLL::Compiler.lineof($orig, self.from());
            my str $prematch  := nqp::substr($orig, $from > 20 ?? $from - 20 !! 0, $from > 20 ?? 20 !! $from);
            my str $postmatch := nqp::substr($orig, $to, 20);
            my $label     := $*W.find_symbol(['Label']).new( :name($*LABEL), :$line, :$prematch, :$postmatch );
            $*W.add_object($label);
            $*W.install_lexical_symbol($*W.cur_lexpad(), $*LABEL, $label);
        }
    }

    token statement($*LABEL = '') {
        :my $*QSIGIL := '';
        :my $*SCOPE := '';
        :my $*ACTIONS := %*LANG<MAIN-actions>;
        :my $*STATEMENT_ID := $*NEXT_STATEMENT_ID++;
        :my $*IN_STMT_MOD := 0;
        :my $*ESCAPEBLOCK := 0;
        <!before <[\])}]> | $ >
        <!stopper>
        <!!{ nqp::rebless($/.CURSOR, %*LANG<MAIN>) }>
        [
        | <label> <statement($*LABEL)> { $*LABEL := '' if $*LABEL }
        | <statement_control>
        | <EXPR> :dba('statement end') { $*IN_STMT_MOD := 1 }
            [
            || <?MARKED('endstmt')>
            || :dba('statement modifier') <.ws> <statement_mod_cond> <statement_mod_loop>?
            || :dba('statement modifier loop') <.ws> <statement_mod_loop>
                {
                    my $sp := $<EXPR><statement_prefix>;
                    if $sp && $sp<sym> eq 'do' {
                        my $s := $<statement_mod_loop><sym>;
                        $/.CURSOR.obs("do..." ~ $s, "repeat...while or repeat...until");
                    }
                }
            ]?
        | <?[;]>
        | <?stopper>
        | {} <.panic: "Bogus statement">
        ]
    }

    token eat_terminator {
        || ';'
        || <?MARKED('endstmt')> <.ws>
        || <?before ')' | ']' | '}' >
        || $
        || <?stopper>
        || <?before [if|while|for|loop|repeat|given|when] » > { self.typed_panic( 'X::Syntax::Confused', reason => "Missing semicolon" ) }
        || { $/.CURSOR.typed_panic( 'X::Syntax::Confused', reason => "Confused" ) }
    }

    token xblock($*IMPLICIT = 0) {
        :my $*GOAL := '{';
        :my $*BORG := {};
        <EXPR> <.ws> <pblock($*IMPLICIT)>
    }

    token pblock($*IMPLICIT = 0) {
        :my $*DECLARAND := $*W.stub_code_object('Block');
        :my $*CODE_OBJECT := $*DECLARAND;
        :my $*SIG_OBJ;
        :my %*SIG_INFO;
        :my $*POD_BLOCK;
        :my $*DOC := $*DECLARATOR_DOCS;
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        {
            $*DECLARATOR_DOCS := '';

            if $*PRECEDING_DECL_LINE < $*LINE_NO {
                $*PRECEDING_DECL_LINE := $*LINE_NO;
                $*PRECEDING_DECL := $*DECLARAND;
            }
        }
        <.attach_leading_docs>
        :dba('block or pointy block')
        [
        | <lambda>
            <.newpad>
            :my $*SCOPE := 'my';
            :my $*GOAL := '{';
            <signature> {
                %*SIG_INFO := $<signature>.ast;
                $*SIG_OBJ := $*W.create_signature_and_params($<signature>,
                    %*SIG_INFO, $*W.cur_lexpad(), 'Mu', :rw($<lambda> eq '<->'));
            }
            <blockoid>
        | <?[{]>
            <.newpad>
            <blockoid>
        || <.missing_block>
        ]
    }

    token lambda { '->' | '<->' }

    token block($*IMPLICIT = 0) {
        :my $*DECLARAND := $*W.stub_code_object('Block');
        :my $*CODE_OBJECT := $*DECLARAND;
        :dba('scoped block')
        [ <?[{]> || <.missing_block>]
        <.newpad>
        <blockoid>
    }

    token blockoid {
        :my $*CURPAD;
        :my %*HANDLERS;
        :my %*PRAGMAS := self.shallow_copy(nqp::getlexdyn('%*PRAGMAS'));
        <.finishpad>
        [
        | '{YOU_ARE_HERE}' <you_are_here>
        | :dba('block')
            '{'
            <!!{ $*VARIABLE := '' if $*VARIABLE; 1 }>
            <statementlist(1)>
            [<.cheat_heredoc> || '}']
            <?ENDSTMT>
        || <.missing_block>
        ]
        { $*CURPAD := $*W.pop_lexpad() }
    }

    token unitstart { <?> }
    token you_are_here {
        <?{ nqp::getlexdyn('$?FILES') ~~ /\.setting$/ }> ||
            { self.typed_panic('X::Syntax::Reserved',
                reserved => 'use of {YOU_ARE_HERE} outside of a setting',
                instead => ' (use whitespace if not a setting, or rename file with .setting extension?)');
            }
    }
    token newpad { <?> { $*W.push_lexpad($/) } }
    token finishpad { <?> }

    token bom { \xFEFF }

    proto token terminator { <...> }

    token terminator:sym<;> { <?[;]> }
    token terminator:sym<)> { <?[)]> }
    token terminator:sym<]> { <?[\]]> }
    token terminator:sym<}> { <?[}]> }
    token terminator:sym<ang> { <?[>]> <?{ $*IN_REGEX_ASSERTION }> }
    token terminator:sym<if>     { 'if'     <.kok> }
    token terminator:sym<unless> { 'unless' <.kok> }
    token terminator:sym<while>  { 'while'  <.kok> }
    token terminator:sym<until>  { 'until'  <.kok> }
    token terminator:sym<for>    { 'for'    <.kok> }
    token terminator:sym<given>  { 'given'  <.kok> }
    token terminator:sym<when>   { 'when'   <.kok> }
    token terminator:sym<with>   { 'with'   <.kok> }
    token terminator:sym<without> { 'without' <.kok> }
    token terminator:sym<arrow>  { '-->' }


    token stdstopper {
        [
        || <?MARKED('endstmt')> <?>
        || [
           | <?terminator>
           | $
           ]
       ]
    }

    ## Statement control

    proto rule statement_control { <...> }

    rule statement_control:sym<if> {
        $<sym>=[if|with]<.kok> {}
        <xblock(so ~$<sym>[0] ~~ /with/)>
        [
            [
            | 'else'\h*'if' <.typed_panic: 'X::Syntax::Malformed::Elsif'>
            | 'elif' { $/.CURSOR.typed_panic('X::Syntax::Malformed::Elsif', what => "elif") }
            | $<sym>='elsif' <xblock>
            | $<sym>='orwith' <xblock(1)>
            ]
        ]*
        {}
        [ 'else' <else=.pblock(so ~$<sym>[-1] ~~ /with/)> ]?
    }

    rule statement_control:sym<unless> {
        $<sym>=[unless|without]<.kok> {}
        <xblock($<sym> eq 'without')>
        [ <!before [els[e|if]|orwith]» > || <.typed_panic: 'X::Syntax::UnlessElse'> ]
    }

    rule statement_control:sym<while> {
        $<sym>=[while|until]<.kok> {}
        <xblock>
    }

    rule statement_control:sym<repeat> {
        <sym><.kok> {}
        [
        | $<wu>=[while|until]<.kok> <xblock>
        | <pblock>
          [$<wu>=['while'|'until']<.kok> || <.missing('"while" or "until"')>]
          <EXPR>
        ]
    }

    rule statement_control:sym<for> {
        <sym><.kok> {}
        [ <?before 'my'? '$'\w+ '(' >
            <.typed_panic: 'X::Syntax::P5'> ]?
        [ <?before '(' <.EXPR>? ';' <.EXPR>? ';' <.EXPR>? ')' >
            <.obs('C-style "for (;;)" loop', '"loop (;;)"')> ]?
        <xblock(1)>
    }

    rule statement_control:sym<whenever> {
        <sym><.kok> {}
        <xblock(1)>
    }

    rule statement_control:sym<foreach> {
        <sym><.end_keyword> <.obs("'foreach'", "'for'")>
    }

    token statement_control:sym<loop> {
        <sym><.kok>
        :s''
        [ '('
            [
            <e1=.EXPR>? ';' <e2=.EXPR>? ';' <e3=.EXPR>?
            || <.malformed('loop spec')>
            ]
        ')' ]?
        <block>
    }

    rule statement_control:sym<need> {
        <sym>
        [
        | <version>
        | <module_name>
        ] +% ','
        {
            for $<module_name> {
                my $lnd  := $*W.dissect_longname($_<longname>);
                my $name := $lnd.name;
                my %cp   := $lnd.colonpairs_hash('need');
                $*W.load_module($/, $name, %cp, $*GLOBALish);
            }
        }
    }

    token statement_control:sym<import> {
        :my $*IN_DECL := 'import';
        <sym> <.ws>
        <module_name> [ <.spacey> <arglist> ]? <.ws>
        :my $*HAS_SELF := '';
        {
            my $longname := $*W.dissect_longname($<module_name><longname>);
            my $module;
            my $found := 0;
            try {
                $module := $*W.find_symbol($longname.components());
                $found := 1;
            }
            if $found {
                # todo: fix arglist
                $*W.do_import($/, $*W.find_symbol(<CompUnit Handle>).from-unit($module.WHO), $longname.name, $*W.arglist($/));
            }
            else {
                $/.CURSOR.panic("Could not find module " ~ ~$<module_name> ~
                    " to import symbols from");
            }
        }
    }

    token statement_control:sym<no> {
        :my $*IN_DECL := 'no';
        :my $longname;
        <sym> <.ws>
        [
        | <module_name> [ <.spacey> <arglist> ]? <.explain_mystery> <.cry_sorrows>
            { $*W.do_pragma_or_load_module($/,0) }
        ]
        <.ws>
    }

    token statement_control:sym<use> {
        :my $longname;
        :my $*IN_DECL := 'use';
        :my $*HAS_SELF := '';
        :my $*SCOPE   := 'use';
        :my $OLD_MAIN := ~$*MAIN;
        :my %*MYSTERY;
        $<doc>=[ 'DOC' \h+ ]**0..1
        <sym> <.ws>
        [
        | <version> [
                    ||  <?{ $<version><vnum>[0] == 5 }> {
                            my $module := $*W.load_module($/, 'Perl5', {}, $*GLOBALish);
                            $*W.do_import($/, $module, 'Perl5');
                            $*W.import_EXPORTHOW($/, $module);
                        }
                    ||  <?{ $<version><vnum>[0] == 6 }> {
                            my $version_parts := $<version><vnum>;
                            my $vwant := $<version>.ast.compile_time_value;
                            my $vhave := $*W.find_symbol(['Version']).new(
                                nqp::getcomp('perl6').language_version());
                            my $sm := $*W.find_symbol(['&infix:<~~>']);
                            if !$sm($vhave,$vwant) {
                                $/.CURSOR.typed_panic: 'X::Language::Unsupported', version => ~$<version>;
                            }
                            $*MAIN   := 'MAIN';
                            $*STRICT := 1 if $*begin_compunit;
                        }
                    ||  {
                            $/.CURSOR.typed_panic: 'X::Language::Unsupported', version => ~$<version>;
                        }
                    ]
        | <module_name>
            [
            || <.spacey> <arglist> <.cheat_heredoc>? <?{ $<arglist><EXPR> }> <.explain_mystery> <.cry_sorrows>
                {
                    $*W.do_pragma_or_load_module($/,1);
                }
            || {
                    unless ~$<doc> && !%*COMPILING<%?OPTIONS><doc> {
                        $*W.do_pragma_or_load_module($/,1);
                    }
                }
            ]
        ]
        [ <?{ $*MAIN ne $OLD_MAIN }>
          <.eat_terminator>
          <statementlist=.FOREIGN_LANG($*MAIN, 'statementlist', 1)>
        || <?> ]
        <.ws>
    }

    # This is like HLL::Grammar.LANG but it allows to call a token of a Perl 6 level grammar.
    method FOREIGN_LANG($lang, $regex, *@args) {
        if nqp::istype(%*LANG{$lang}, NQPCursor) {
            return self.LANG($lang, $regex, @args)
        }
        else {
            my $Str := $*W.find_symbol(['Str']);
            my $lang_cursor := %*LANG{$lang}.'!cursor_init'($Str.new( :value(self.orig())), :p(self.pos()));
            if self.HOW.traced(self) {
                $lang_cursor.HOW.trace-on($lang_cursor, self.HOW.trace_depth(self));
            }
            my $*ACTIONS := %*LANG{$lang ~ '-actions'};
            my $ret := $lang_cursor."$regex"(|@args);

            # Build up something NQP-levelish we can return.
            my $new := NQPCursor.'!cursor_init'(self.orig(), :p(self.pos()), :shared(self.'!shared'()));
            my $p6cursor := $*W.find_symbol(['Cursor']);
            nqp::bindattr_i($new, NQPCursor, '$!from',  nqp::getattr_i($ret, $p6cursor, '$!from'));
            nqp::bindattr_i($new, NQPCursor, '$!pos',   nqp::getattr_i($ret, $p6cursor, '$!pos'));
            nqp::bindattr($new,   NQPCursor, '$!name',  nqp::getattr($ret,   $p6cursor, '$!name'));

            my $match := nqp::create(NQPMatch);
            nqp::bindattr($match, NQPMatch, '$!made', nqp::getattr($ret, $p6cursor, '$!made'));
            nqp::bindattr($new, NQPCursor, '$!match', $match);
            $new;
        }
    }

    rule statement_control:sym<require> {
        <sym>
        [
        | <module_name>
        | <file=.variable>
        | <!sigil> <file=.term>
        ]
        <EXPR>?
    }

    rule statement_control:sym<given> {
        <sym><.kok> <xblock(1)>
    }
    rule statement_control:sym<when> {
        <sym><.kok> <xblock>
    }
    rule statement_control:sym<default> {
        <sym><.kok> <block>
    }

    rule statement_control:sym<CATCH> {<sym> <block(1)> }
    rule statement_control:sym<CONTROL> {<sym> <block(1)> }
    rule statement_control:sym<QUIT> {<sym> <block(1)> }

    proto token statement_prefix { <...> }
    token statement_prefix:sym<BEGIN>   { :my %*MYSTERY; <sym><.kok> <blorst> <.explain_mystery> <.cry_sorrows> }
    token statement_prefix:sym<COMPOSE> { <sym><.kok> <blorst> }
    token statement_prefix:sym<TEMP>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<CHECK>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<INIT>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<ENTER>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<FIRST>   { <sym><.kok> <blorst> }

    token statement_prefix:sym<END>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<LEAVE> { <sym><.kok> <blorst> }
    token statement_prefix:sym<KEEP>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<UNDO>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<NEXT>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<LAST>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<PRE>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<POST>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<CLOSE> { <sym><.kok> <blorst> }

    token statement_prefix:sym<race>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<hyper>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<eager>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<lazy>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<sink>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<try>     {
        :my %*PRAGMAS := self.shallow_copy(nqp::getlexdyn('%*PRAGMAS'));
        <sym><.kok> { %*PRAGMAS<fatal> := 1; } <blorst>
    }
    token statement_prefix:sym<quietly> { <sym><.kok> <blorst> }
    token statement_prefix:sym<gather>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<once>    { <sym><.kok> <blorst> }
    token statement_prefix:sym<start>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<supply>  { <sym><.kok> <blorst> }
    token statement_prefix:sym<react>   { <sym><.kok> <blorst> }
    token statement_prefix:sym<do>      { <sym><.kok> <blorst> }
    token statement_prefix:sym<DOC>     {
        <sym><.kok> $<phase>=['BEGIN' || 'CHECK' || 'INIT']<.end_keyword><.ws>
        <blorst>
    }

    token blorst {
        [ <?[{]> <block> | <![;]> <statement> <.cheat_heredoc>? || <.missing: 'block or statement'> ]
    }

    ## Statement modifiers

    proto rule statement_mod_cond { <...> }

    token modifier_expr { <EXPR> }
    token smexpr { <EXPR> }

    rule statement_mod_cond:sym<if>     { <sym><.kok> <modifier_expr> }
    rule statement_mod_cond:sym<unless> { <sym><.kok> <modifier_expr> }
    rule statement_mod_cond:sym<when>   { <sym><.kok> <modifier_expr> }
    rule statement_mod_cond:sym<with>   { <sym><.kok> <modifier_expr> }
    rule statement_mod_cond:sym<without>{ <sym><.kok> <modifier_expr> }

    proto rule statement_mod_loop { <...> }

    rule statement_mod_loop:sym<while> { <sym><.kok> <smexpr> }
    rule statement_mod_loop:sym<until> { <sym><.kok> <smexpr> }
    rule statement_mod_loop:sym<for>   { <sym><.kok> <smexpr> }
    rule statement_mod_loop:sym<given> { <sym><.kok> <smexpr> }

    ## Terms

    token term:sym<fatarrow>           { <fatarrow> }
    token term:sym<colonpair>          { <colonpair> }
    token term:sym<variable>           { <variable> { $*VAR := $<variable> } }
    token term:sym<package_declarator> { <package_declarator> }
    token term:sym<scope_declarator>   { <scope_declarator> }
    token term:sym<routine_declarator> { <routine_declarator> }
    token term:sym<multi_declarator>   { <?before 'multi'|'proto'|'only'> <multi_declarator> }
    token term:sym<regex_declarator>   { <regex_declarator> }
    token term:sym<circumfix>          { <circumfix> }
    token term:sym<statement_prefix>   { <statement_prefix> }
    token term:sym<**>                 { <sym> }
    token term:sym<*>                  { <sym> }
    token term:sym<lambda>             { <?lambda> <pblock> {$*BORG<block> := $<pblock> } }
    token term:sym<type_declarator>    { <type_declarator> }
    token term:sym<value>              { <value> }
    token term:sym<unquote>            { '{{{' <?{ $*IN_QUASI }> <statementlist> '}}}' }
    token term:sym<!!>                 { '!!' <?before \s> }  # actual error produced inside infix:<?? !!>
    token term:sym<∞>                  { <sym> }

    token term:sym<::?IDENT> {
        $<sym> = [ '::?' <identifier> ] »
    }
    token term:sym<p5end> {
        << __END__ >>
        <.obs('__END__ as end of code',
          'the =finish pod marker and $=finish to read')>
    }
    token term:sym<p5data> {
        << __DATA__ >>
        <.obs('__DATA__ as start of data',
          'the =finish pod marker and $=finish to read')>
    }

    token infix:sym<lambda> {
        <?before '{' | '->' > <!{ $*IN_META }> {
            my $needparens := 0;
            my $pos := $/.from;
            my $line := HLL::Compiler.lineof($/.orig, $/.from, :cache(1));
            my $lex := $*W.cur_lexpad();
            for 'if', 'unless', 'while', 'until', 'for', 'given', 'when', 'loop', 'sub', 'method', 'with', 'without', 'supply', 'whenever', 'react' {
                $needparens++ if $_ eq 'loop';
                my $m := %*MYSTERY{$_ ~ '-' ~ $lex.cuid};
                next unless $m;
                my $m_pos  := $m<pos>[nqp::elems($m<pos>) - 1];
                my $m_line := HLL::Compiler.lineof($/.orig, $m_pos, :cache(1));
                if $line - $m_line < 5 {
                    if $m<ctx> eq '(' {
                        $/.CURSOR.'!clear_highwater'();
                        $/.CURSOR.'!cursor_pos'($m_pos);
                        $/.CURSOR.typed_sorry('X::Syntax::KeywordAsFunction',
                                word => $_,
                                :$needparens,
                        );
                        $/.CURSOR.'!cursor_pos'($pos);
                        $/.CURSOR.panic("Unexpected block in infix position (two terms in a row)");
                    }
                    else {
                        $/.CURSOR.'!clear_highwater'();
                        $/.CURSOR.'!cursor_pos'($m_pos);
                        $/.CURSOR.sorry("Word '$_' interpreted as a listop; please use 'do $_' to introduce the statement control word");
                        $/.CURSOR.'!cursor_pos'($pos);
                        $/.CURSOR.panic("Unexpected block in infix position (two terms in a row)");
                    }
                }
            }
        }
        [
        || <!{ $*IN_REDUCE }> {
            $/.CURSOR.panic("Unexpected block in infix position (missing statement control word before the expression?)");
        }
        || <!>
        ]
    }

    token term:sym<undef> {
        <sym> >> {}
        [ <?before \h*'$/' >
            <.obs('$/ variable as input record separator',
                 "the filehandle's .slurp method")>
        ]?
        [ <?before [ '(' || \h*<sigil><twigil>?\w ] >
            <.obs('undef as a verb', 'undefine() or assignment of Nil')>
        ]?
        <.obs('undef as a value', "something more specific:\n\tan undefined type object such as Any or Int,\n\t:!defined as a matcher,\n\tAny:U as a type constraint,\n\tNil as the absence of an expected value\n\tor fail() as a failure return\n\t   ")>
    }

    token term:sym<new> {
        'new' \h+ <longname> \h* <![:]> <.obs("C++ constructor syntax", "method call syntax")>
    }

    token fatarrow {
        <key=.identifier> \h* '=>' <.ws> <val=.EXPR('i<=')>
    }

    token coloncircumfix($front) {
        [
        | '<>' <.worry("Pair with <> really means an empty list, not null string; use :$front" ~ "('') to represent the null string,\n  or :$front" ~ "() to represent the empty list more accurately")>
        | {} <circumfix>
        ]
    }

    token colonpair {
        :my $*key;
        :my $*value;

        ':'
        :dba('colon pair')
        [
        | '!' [ <identifier> || <.panic: "Malformed False pair; expected identifier"> ]
            [ <[ \[ \( \< \{ ]> {
            $/.CURSOR.typed_panic('X::Syntax::NegatedPair', key => ~$<identifier>) } ]?
            { $*key := $<identifier>.Str; $*value := 0; }
        | $<num> = [\d+] <identifier> [ <?before <[ \[ \( \< \{ ]>> {} <.sorry("Extra argument not allowed; pair already has argument of " ~ $<num>.Str)> <.circumfix> ]?
            { $*key := $<identifier>.Str; $*value := +$<num>; }
        | <identifier>
            { $*key := $<identifier>.Str; }
            [
            || <.unsp>? :dba('pair value') <coloncircumfix($*key)> { $*value := $<coloncircumfix>; }
            || { $*value := 1; }
            ]
        | :dba('signature') '(' ~ ')' <fakesignature>
        | <coloncircumfix('')>
            { $*key := ""; $*value := $<coloncircumfix>; }
        | <var=.colonpair_variable>
            { $*key := $<var><desigilname>.Str; $*value := $<var>; self.check_variable($*value); }
        ]
    }

    token colonpair_variable {
        <sigil> {}
        [
        | <twigil>? <desigilname>
        | $<capvar>='<' <desigilname> '>'
        ]
    }

    proto token special_variable { <...> }

    token special_variable:sym<$!{ }> {
        [ '$!{' .*? '}' | '%!' ]
        <.obsvar('%!')>
    }

    token special_variable:sym<$~> {
        <sym> <?before \h* '='>
        <.obsvar('$~')>
    }

    token special_variable:sym<$`> {
        <sym>  <?before \s | ',' | <terminator> >
        <.obsvar('$`')>
    }

    token special_variable:sym<$@> {
        <sym> <[ \s ; , ) ]> .
        <.obsvar('$@')>
    }

    # TODO: use actual variable in error message
    token special_variable:sym<$#> {
        <sym>
        <.obs('$#variable', '@variable.end')>
    }

    token special_variable:sym<$$> {
        <sym> \W
        <.obsvar('$$')>
    }
    token special_variable:sym<$%> {
        <sym> <?before \h* '='>
        <.obsvar('$%')>
    }

    # TODO: $^X and other "caret" variables

    token special_variable:sym<$^> {
        <sym> <?before \h* '='>
        <.obsvar('$^')>
    }

    token special_variable:sym<$&> {
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('$&')>
    }

    token special_variable:sym<$*> {
        <sym> <?before \h* '='>
        <.obsvar('$*')>
    }

    token special_variable:sym<$=> {
        <sym> <?before \h+ '='>
        <.obsvar('$=')>
    }

    token special_variable:sym<@+> {
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('@+')>
    }

    token special_variable:sym<%+> {
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('%+')>
    }

    token special_variable:sym<$+[ ]> {
        '$+['
        <.obsvar('@+')>
    }

    token special_variable:sym<@+[ ]> {
        '@+['
        <.obsvar('@+')>
    }

    token special_variable:sym<@+{ }> {
        '@+{'
        <.obsvar('%+')>
    }

    token special_variable:sym<@-> {
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('@-')>
    }

    token special_variable:sym<%-> {
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('%-')>
    }

    token special_variable:sym<$-[ ]> {
        '$-['
        <.obsvar('@-')>
    }

    token special_variable:sym<@-[ ]> {
        '@-['
        <.obsvar('@-')>
    }

    token special_variable:sym<%-{ }> {
        '@-{'
        <.obsvar('%-')>
    }

    token special_variable:sym<$/> {
        <sym> <?before \h* '=' \h* <[ ' " ]> >
        <.obsvar('$/')>
    }

    token special_variable:sym<$\\> {
        '$\\' <?before \s | ',' | '=' | <terminator> >
        <.obsvar('$\\')>
    }

    token special_variable:sym<$|> {
        <sym> <?before \h* '='>
        <.obsvar('$|')>
    }

    token special_variable:sym<$:> {
        <sym> <?before \h* '='>
        <.obsvar('$:')>
    }

    token special_variable:sym<$;> {
        <sym> <?before \h* '='>
        <.obsvar('$;')>
    }

    token special_variable:sym<$'> { #'
        <sym> <?before \s | ',' | <terminator> >
        <.obsvar('$' ~ "'")>
    }

    token special_variable:sym<$"> {
        <sym> <?before \h* '='>
        <.obsvar('$"')>
    }

    token special_variable:sym<$,> {
        <sym> <?before \h* '='>
        <.obsvar('$,')>
    }

    token special_variable:sym<$.> {
        <sym> {} <!before \w | '('>
        <.obsvar('$.')>
    }

    token special_variable:sym<$?> {
        <sym> {} <!before \w | '('>
        <.obsvar('$?')>
    }

    token special_variable:sym<$]> {
        <sym> {} <!before \w | '('>
        <.obsvar('$]')>
    }

    regex special_variable:sym<${ }> {
        <sigil> '{' {} $<text>=[.*?] '}'
        <!{ $*IN_DECL }>
        <!{ $<text> ~~ / '=>' || ':'<:alpha> || '|%' / }>
        <!{ $<text> ~~ / ^ \s* $ / }>
        <?{
            my $sigil := $<sigil>.Str;
            my $text := $<text>.Str;
            my $bad := $sigil ~ '{' ~ $text ~ '}';
            $text := $text - 1 if $text ~~ /^\d+$/ && $text > 0;
            if $sigil ne '$' && $sigil ne '@' {
                False;  # not likely a P5ism
            }
            elsif !($text ~~ /^(\w|\:)+$/) {
                $/.CURSOR.obs($bad, "$sigil\($text) for hard ref or $sigil\::($text) for symbolic ref");
            }
            elsif $*QSIGIL {
                $/.CURSOR.obs($bad, '{' ~ $sigil ~ $text ~ '}');
            }
            else {
                $/.CURSOR.obs($bad, $sigil ~ $text);
            }
        }>
    }

    token desigilname {
        [
        | <?before <.sigil> <.sigil> > <variable>
        | <?sigil>
            [ <?{ $*IN_DECL }> <.typed_panic: 'X::Syntax::Variable::IndirectDeclaration'> ]?
            <variable> {
                $*VAR := $<variable>;
                self.check_variable($*VAR);
            }
        | <longname>
        ]
    }

    token variable {
        :my $*IN_META := '';
        [
        | :dba('infix noun') '&[' ~ ']' <infixish('[]')>
        | <sigil> <twigil>? <desigilname>
          [ <?{ !$*IN_DECL && $*VARIABLE && $*VARIABLE eq $<sigil> ~ $<twigil> ~ $<desigilname> }>
            { self.typed_panic: 'X::Syntax::Variable::Initializer', name => $*VARIABLE } ]?
        | <special_variable>
        | <sigil> $<index>=[\d+]                              [<?{ $*IN_DECL }> <.typed_panic: "X::Syntax::Variable::Numeric">]?
        | <sigil> <?[<]> <postcircumfix>                      [<?{ $*IN_DECL }> <.typed_panic('X::Syntax::Variable::Match')>]?
        | <?before <sigil> <?[ ( [ { ]>> <!RESTRICTED> <?{ !$*IN_DECL }> <contextualizer>
        | $<sigil>=['$'] $<desigilname>=[<[/_!¢]>]
        | {} <sigil> <!{ $*QSIGIL }> <?MARKER('baresigil')>   # try last, to allow sublanguages to redefine sigils (like & in regex)
        ]
        [ <?{ $<twigil> && $<twigil> eq '.' }>
            [ <.unsp> | '\\' | <?> ] <?[(]> <!RESTRICTED> <arglist=.postcircumfix>
        ]?
        { $*LEFTSIGIL := nqp::substr(self.orig(), self.from, 1) unless $*LEFTSIGIL }
    }

    token contextualizer {
        :dba('contextualizer')
        [ <?{ $*IN_DECL }> <.panic: "Cannot declare a contextualizer"> ]?
        [
        | <sigil> '(' ~ ')'    <coercee=sequence>
        | <sigil> <?[ \[ \{ ]> <coercee=circumfix>
        ]
    }

    token sigil { <[$@%&]> }

    proto token twigil { <...> }
    token twigil:sym<.> { <sym> <?before \w> }
    token twigil:sym<!> { <sym> <?before \w> }
    token twigil:sym<^> { <sym> <?before \w> }
    token twigil:sym<:> { <sym> <?before \w> }
    token twigil:sym<*> { <sym> <?before \w> }
    token twigil:sym<?> { <sym> <?before \w> }
    token twigil:sym<=> { <sym> <?before \w> }
    token twigil:sym<~> { <sym> <?before \w> }

    proto token package_declarator { <...> }
    token package_declarator:sym<package> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'package';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<module> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'module';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<class> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'class';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<grammar> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'grammar';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<role> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'role';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<knowhow> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'knowhow';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<native> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'native';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<slang> {
        :my $*OUTERPACKAGE := $*PACKAGE;
        :my $*PKGDECL := 'slang';
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> <package_def>
    }
    token package_declarator:sym<trusts> {
        <sym><.kok> [ <typename> || <.typo_typename(1)> ]
    }
    rule package_declarator:sym<also> {
        <sym><.kok>
        [ <trait>+ || <.panic: "No valid trait found after also"> ]
    }

    rule package_def {
        :my $longname;
        :my $outer := $*W.cur_lexpad();
        :my $*IMPLICIT := 0;
        :my $*DECLARAND;
        :my $*CODE_OBJECT := $*W.stub_code_object($*PKGDECL eq 'role' ?? 'Sub' !! 'Block');
        :my $*IN_DECL := 'package';
        :my $*HAS_SELF := '';
        :my $*CURPAD;
        :my $*DOC := $*DECLARATOR_DOCS;
        :my $*POD_BLOCK;
        :my $*BORG := {};
        { $*DECLARATOR_DOCS := '' }
        <.attach_leading_docs>

        # Type-object will live in here; also set default REPR (a trait
        # may override this, e.g. is repr('...')).
        :my $*PACKAGE;
        :my %*ATTR_USAGES;
        :my $*REPR;
        :my $*VER;
        :my $*AUTH;

        # Default to our scoped.
        { unless $*SCOPE { $*SCOPE := 'our'; } }

        [
            [ <longname> { $longname := $*W.dissect_longname($<longname>); } ]?
            <.newpad>

            [ :dba('generic role')
            <?{ ($*PKGDECL//'') eq 'role' }>
            { $*PACKAGE := $*OUTERPACKAGE } # in case signature tries to declare a package
            '[' ~ ']' <signature>
            { $*IN_DECL := ''; }
            ]?

            <trait>*

            {

                # Unless we're augmenting...
                if $*SCOPE ne 'augment' {
                    if $longname {
                        for $longname.colonpairs_hash('class') -> $adverb {
                            my str $key := $adverb.key;
                            if $key eq 'ver' {
                                $*VER := $*W.handle-begin-time-exceptions($/,
                                    'parsing package version',
                                    -> { $*W.find_symbol(['Version']).new($adverb.value) });
                            }
                            elsif $key eq 'auth' {
                                $*AUTH := $adverb.value;
                            }
                            else {
                                $/.CURSOR.typed_panic('X::Syntax::Type::Adverb', adverb => $adverb.key);
                            }
                        }
                    }

                    # Locate any existing symbol. Note that it's only a match
                    # with "my" if we already have a declaration in this scope.
                    my $exists := 0;
                    my @name := $longname ??
                        $longname.type_name_parts('package name', :decl(1)) !!
                        [];
                    my $target_package := $longname && $longname.is_declared_in_global()
                        ?? $*GLOBALish
                        !! $*OUTERPACKAGE;
                    if @name && $*SCOPE ne 'anon' {
                        if @name && $*W.already_declared($*SCOPE, $target_package, $outer, @name) {
                            $*PACKAGE := $*W.find_symbol(@name);
                            $exists := 1;
                        }
                    }
                    my $fullname;
                    if @name {
                        $fullname := $longname.fully_qualified_with($target_package);
                    }

                    # If it exists already, then it's either uncomposed (in which
                    # case we just stubbed it), a role (in which case multiple
                    # variants are OK) or else an illegal redecl.
                    if $exists && ($*PKGDECL ne 'role' || !nqp::can($*PACKAGE.HOW, 'configure_punning')) {
                        if $*PKGDECL eq 'role' || !nqp::can($*PACKAGE.HOW, 'is_composed') || $*PACKAGE.HOW.is_composed($*PACKAGE) {
                            $*W.throw($/, ['X', 'Redeclaration'],
                                symbol => $longname.name(),
                            );
                        }
                        if nqp::defined($*REPR) {
                            $*W.throw($/, ['X', 'TooLateForREPR'], type => $*PACKAGE);
                        }
                    }

                    # If it's not a role, or it is a role but one with no name,
                    # then just needs meta-object construction and installation.
                    elsif $*PKGDECL ne 'role' || !@name {
                        # Construct meta-object for this package.
                        my %args;
                        if @name {
                            %args<name> := $fullname;
                            %args<ver> := $*VER;
                            %args<auth> := $*AUTH;
                        }
                        if $*REPR ne '' {
                            %args<repr> := $*REPR;
                        }
                        $*PACKAGE := $*W.pkg_create_mo($/, $*W.resolve_mo($/, $*PKGDECL), |%args);

                        # Install it in the symbol table if needed.
                        if @name {
                            $*W.install_package($/, @name, $*SCOPE, $*PKGDECL, $target_package, $outer, $*PACKAGE);
                        }
                    }

                    # If it's a named role, a little trickier. We need to make
                    # a parametric role group for it (unless we got one), and
                    # then install it in that.
                    else {
                        # If the group doesn't exist, create it.
                        my $group;
                        if $exists {
                            $group := $*PACKAGE;
                        }
                        else {
                            $group := $*W.pkg_create_mo($/, $*W.resolve_mo($/, 'role-group'),
                                :name($fullname), :repr($*REPR));
                            $*W.install_package($/, @name, $*SCOPE, $*PKGDECL, $target_package, $outer, $group);
                        }

                        # Construct role meta-object with group.
                        sub needs_args($s) {
                            return 0 if !$s;
                            my @params := $s.ast<parameters>;
                            return 0 if nqp::elems(@params) == 0;
                            return nqp::elems(@params) > 1 || !@params[0]<optional>;
                        }
                        $*PACKAGE := $*W.pkg_create_mo($/, $*W.resolve_mo($/, $*PKGDECL),
                            :name($fullname), :ver($*VER), :auth($*AUTH), :repr($*REPR),
                            :group($group), :signatured(needs_args($<signature>)));
                    }
                }
                else {
                    # Augment. Ensure we can.
                    if !%*PRAGMAS<MONKEY-TYPING> && $longname.text ne 'Cool' {
                        $/.CURSOR.typed_panic('X::Syntax::Augment::WithoutMonkeyTyping');
                    }
                    elsif !$longname {
                        $*W.throw($/, 'X::Anon::Augment', package-kind => $*PKGDECL);
                    }

                    if $longname.colonpairs_hash('class') {
                        $/.CURSOR.typed_panic('X::Syntax::Augment::Adverb');
                    }

                    # Locate type.
                    my @name :=
                      $longname.type_name_parts('package name', :decl(1));
                    my $found;
                    try { $*PACKAGE := $*W.find_symbol(@name); $found := 1 }
                    unless $found {
                        $*W.throw($/, 'X::Augment::NoSuchType',
                            package-kind => $*PKGDECL,
                            package      => $longname.text(),
                        );
                    }
                    unless $*PACKAGE.HOW.archetypes.augmentable {
                        $/.CURSOR.typed_panic('X::Syntax::Augment::Illegal',
                            package      => $longname.text);
                    }
                }

                # Install $?PACKAGE, $?ROLE, $?CLASS, and :: variants as needed.
                my $curpad := $*W.cur_lexpad();
                unless $curpad.symbol('$?PACKAGE') {
                    $*W.install_lexical_symbol($curpad, '$?PACKAGE', $*PACKAGE);
                    $*W.install_lexical_symbol($curpad, '::?PACKAGE', $*PACKAGE);
                    if $*PKGDECL eq 'role' {
                        $*W.install_lexical_symbol($curpad, '$?ROLE', $*PACKAGE);
                        $*W.install_lexical_symbol($curpad, '::?ROLE', $*PACKAGE);
                        $*W.install_lexical_symbol($curpad, '$?CLASS',
                            $*W.pkg_create_mo($/, $*W.resolve_mo($/, 'generic'), :name('$?CLASS')));
                        $*W.install_lexical_symbol($curpad, '::?CLASS',
                            $*W.pkg_create_mo($/, $*W.resolve_mo($/, 'generic'), :name('::?CLASS')));
                    }
                    elsif $*PKGDECL ne 'package' && $*PKGDECL ne 'module' {
                        $*W.install_lexical_symbol($curpad, '$?CLASS', $*PACKAGE);
                        $*W.install_lexical_symbol($curpad, '::?CLASS', $*PACKAGE);
                    }
                }

                # Set declarand as the package.
                $*DECLARAND := $*PACKAGE;

                if $*PRECEDING_DECL_LINE < $*LINE_NO {
                    $*PRECEDING_DECL_LINE := $*LINE_NO;
                    $*PRECEDING_DECL := $*DECLARAND;
                }

                # Apply any traits.
                $*W.apply_traits($<trait>, $*DECLARAND);
            }
            :!s
            { nqp::push(@*PACKAGES, $*PACKAGE); }
            [
            || <?[{]>
                [
                {
                    $*IN_DECL := '';
                    $*begin_compunit := 0;
                    if $*SCOPE eq 'unit' {
                        $/.CURSOR.typed_panic("X::Declaration::Scope", scope => 'unit', declaration => "block form of $*PKGDECL");
                    }
                }
                <blockoid>
                ]

            || ';'
                [
                || <?{ $*begin_compunit }>
                    {
                        unless $longname {
                            $/.CURSOR.panic("Compilation unit cannot be anonymous");
                        }
                        unless $*SCOPE eq 'unit' {
                            if $*PKGDECL eq 'package' {
                                $/.CURSOR.panic('This appears to be Perl 5 code. If you intended it to be Perl 6 code, please use a Perl 6 style declaration like "unit package Foo;" or "unit module Foo;", or use the block form instead of the semicolon form.');
                            }
                            $/.CURSOR.panic("Semicolon form of '$*PKGDECL' without 'unit' is illegal.  You probably want to use 'unit $*PKGDECL'");
                        }
                        unless $outer =:= $*UNIT {
                            $/.CURSOR.typed_panic("X::UnitScope::Invalid", what => $*PKGDECL, where => "in a subscope");
                        }
                        $*begin_compunit := 0;
                    }
                    { $*IN_DECL := ''; }
                    <.finishpad>
                    <statementlist(1)>     # whole rest of file, presumably
                    { $*CURPAD := $*W.pop_lexpad() }
                || { $/.CURSOR.typed_panic("X::UnitScope::TooLate", what => $*PKGDECL); }
                ]
            || <.panic("Unable to parse $*PKGDECL definition")>
            ]
            { nqp::pop(@*PACKAGES); }
        ]:!s || { $/.CURSOR.malformed($*PKGDECL) }
    }

    token declarator {
        :my $*LEFTSIGIL := '';
        :my $*VARIABLE := '';
        [
        # STD.pm6 uses <defterm> here, but we need different
        # action methods
        | '\\' <deftermnow>
            [ <.ws> <term_init=initializer> || <.typed_panic: "X::Syntax::Term::MissingInitializer"> ]
        | <variable_declarator>
          [
          || <?{ $*SCOPE eq 'has' }> <.newpad> [<.ws> <initializer>]? { $*ATTR_INIT_BLOCK := $*W.pop_lexpad() }
          || [<.ws> <initializer>]?
          ]
        | '(' ~ ')' <signature('variable')> [ <.ws> <trait>+ ]? [ <.ws> <initializer> ]?
        | <routine_declarator>
        | <regex_declarator>
        | <type_declarator>
        ]
    }

    proto token multi_declarator { <...> }
    token multi_declarator:sym<multi> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> :my $*MULTINESS := 'multi';
        [ <?before '('> { $*W.throw($/, 'X::Anon::Multi', multiness => $*MULTINESS) } ]?
        [ <declarator> || <routine_def('sub')> || <.malformed('multi')> ]
    }
    token multi_declarator:sym<proto> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> :my $*MULTINESS := 'proto'; :my $*IN_PROTO := 1;
        [ <?before '('> { $*W.throw($/, 'X::Anon::Multi', multiness => $*MULTINESS) } ]?
        [ <declarator> || <routine_def('sub')> || <.malformed('proto')> ]
    }
    token multi_declarator:sym<only> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym><.kok> :my $*MULTINESS := 'only';
        [ <declarator> || <routine_def('sub')> || <.malformed('only')>]
    }
    token multi_declarator:sym<null> {
        :my $*MULTINESS := '';
        <declarator>
    }

    proto token scope_declarator { <...> }
    token scope_declarator:sym<my>        { <sym> <scoped('my')> }
    token scope_declarator:sym<our>       { <sym> <scoped('our')> }
    token scope_declarator:sym<has>       {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym>
        :my $*HAS_SELF := 'partial';
        :my $*ATTR_INIT_BLOCK;
        <scoped('has')>
    }
    token scope_declarator:sym<augment>   { <sym> <scoped('augment')> }
    token scope_declarator:sym<anon>      { <sym> <scoped('anon')> }
    token scope_declarator:sym<state>     { <sym> <scoped('state')> }
    token scope_declarator:sym<supersede> {
        <sym> <scoped('supersede')> <.NYI('"supersede"')>
    }
    token scope_declarator:sym<unit>      { <sym> <scoped('unit')> }

    token scoped($*SCOPE) {
        <.end_keyword>
        :dba('scoped declarator')
        [
        :my $*DOC := $*DECLARATOR_DOCS;
        :my $*POD_BLOCK;
        {
            if $*SCOPE eq 'has' {
                $*DECLARATOR_DOCS := '';
                if $*PRECEDING_DECL_LINE < $*LINE_NO {
                    $*PRECEDING_DECL_LINE := $*LINE_NO;
                    $*PRECEDING_DECL := Mu; # actual declarand comes later, in Actions::declare_variable
                }
                self.attach_leading_docs;
            }
        }
        <.ws>
        [
        | <DECL=declarator>
        | <DECL=regex_declarator>
        | <DECL=package_declarator>
        | [<typename><.ws>]+
          {
            if +$<typename> > 1 {
                $/.CURSOR.NYI('Multiple prefix constraints');
            }
            $*OFTYPE := $<typename>[0];
          }
          <DECL=multi_declarator>
        | <DECL=multi_declarator>
        ]
        || <.ws>[<typename><.ws>]* <ident> <?before <.ws> [':'?':'?'=' | <.terminator> | $ ]> {}
            <.malformed("$*SCOPE (did you mean to declare a sigilless \\{~$<ident>} or \${~$<ident>}?)")>
        || <.ws><!typename> <typo_typename> <!>
        || <.malformed($*SCOPE)>
        ]
    }

    token variable_declarator {
        :my $*IN_DECL := 'variable';
        :my $sigil;
        <variable>
        {
            $*VARIABLE := $<variable>.ast.name;
            $/.CURSOR.add_variable($*VARIABLE);
            $sigil := nqp::substr($*VARIABLE, 0, 1);
            $*IN_DECL := '';
        }
        [
            <.unsp>?
            $<shape>=[
            | '(' ~ ')' <signature>
                {
                    if $sigil eq '&' {
                        self.typed_sorry('X::Syntax::Reserved',
                            reserved => '() shape syntax in routine declarations',
                            instead => ' (maybe use :() to declare a longname?)'
                        );
                    }
                    elsif $sigil eq '@' {
                        self.typed_sorry('X::Syntax::Reserved',
                            reserved => '() shape syntax in array declarations');
                    }
                    elsif $sigil eq '%' {
                        self.typed_sorry('X::Syntax::Reserved',
                            reserved => '() shape syntax in hash declarations');
                    }
                    else {
                        self.typed_sorry('X::Syntax::Reserved',
                            reserved => '() shape syntax in variable declarations');
                    }
                }
            | :dba('shape definition') '[' ~ ']' <semilist>
                { $sigil ne '@' && self.typed_sorry('X::Syntax::Reserved',
                    reserved => '[] shape syntax with the ' ~ $sigil ~ ' sigil') }
            | :dba('shape definition') '{' ~ '}' <semilist>
                { $sigil ne '%' && self.typed_sorry('X::Syntax::Reserved',
                    reserved => '{} shape syntax with the ' ~ $sigil ~ ' sigil') }
            | <?[<]> <postcircumfix> <.NYI: "Shaped variable declarations">
            ]+
        ]?

        [ <.ws> <trait>+ ]?
        [ <.ws> <post_constraint('var')>+ ]?
    }

    proto token routine_declarator { <...> }
    token routine_declarator:sym<sub> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym> <.end_keyword> <routine_def('sub')>
    }
    token routine_declarator:sym<method> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym> <.end_keyword> <method_def('method')>
    }
    token routine_declarator:sym<submethod> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym> <.end_keyword> <method_def('submethod')>
    }
    token routine_declarator:sym<macro> {
        :my $*LINE_NO := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <sym> <.end_keyword> <macro_def()>
    }

    rule routine_def($d) {
        :my $*IN_DECL := $d;
        :my $*METHODTYPE;
        :my $*IMPLICIT := 0;
        :my $*DOC := $*DECLARATOR_DOCS;
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND := $*W.stub_code_object('Sub');
        :my $*CODE_OBJECT := $*DECLARAND;
        :my $*CURPAD;
        :my $*SIG_OBJ;
        :my %*SIG_INFO;
        :my $outer := $*W.cur_lexpad();
        :my $*BORG := {};
        {
            if $*PRECEDING_DECL_LINE < $*LINE_NO {
                $*PRECEDING_DECL_LINE := $*LINE_NO;
                $*PRECEDING_DECL := $*DECLARAND;
            }
        }
        <.attach_leading_docs>
        <deflongname>?
        {
            if $<deflongname> && $<deflongname><colonpair>[0]<coloncircumfix> -> $cf {
                # It's an (potentially new) operator, circumfix, etc. that we
                # need to tweak into the grammar.
                my $category := $<deflongname><name>.Str;
                my $opname := $cf<circumfix>
                    ?? $*W.colonpair_nibble_to_str($/, $cf<circumfix><nibble> // $cf<circumfix><semilist>)
                    !! '';
                my $canname := $category ~ $*W.canonicalize_pair('sym', $opname);
                $/.CURSOR.add_categorical($category, $opname, $canname, $<deflongname>.ast, $*DECLARAND);
            }
        }
        <.newpad>
        [
            '(' <multisig> ')' {
                %*SIG_INFO := $<multisig>.ast;
                $*SIG_OBJ := $*W.create_signature_and_params($<multisig>,
                    %*SIG_INFO, $*W.cur_lexpad(), 'Any');
            }
        ]?
        <trait>* :!s
        { $*IN_DECL := ''; }
        [
        || ';'
            {
                $/.CURSOR.missing_block() if $*BORG<block>;
                if $<deflongname> ne 'MAIN' {
                    $/.CURSOR.typed_panic("X::UnitScope::Invalid", what => "sub", where => "except on a MAIN sub");
                }
                unless $*begin_compunit {
                    $/.CURSOR.typed_panic("X::UnitScope::TooLate", what => "sub");
                }
                unless $*MULTINESS eq '' || $*MULTINESS eq 'only' {
                    $/.CURSOR.typed_panic("X::UnitScope::Invalid", what => "sub", where => "on a $*MULTINESS sub");
                }
                unless $outer =:= $*UNIT {
                    $/.CURSOR.typed_panic("X::UnitScope::Invalid", what => "sub", where => "in a subscope");
                }
                $*begin_compunit := 0;
            }
            <.finishpad>
            <statementlist(1)>
            { $*CURPAD := $*W.pop_lexpad() }
        || <onlystar>
        || <!before '{'> <possibly_subname=.deflongname> { if self.parse($<deflongname>.Str, :rule('typename')) { $/.CURSOR.panic("Did you mean to write \"my $<deflongname> sub $<possibly_subname>\" or put \"returns $<deflongname>\" before the block?"); } } <!>
        || <blockoid>
        ]
    }

    rule method_def($d) {
        :my $*IN_DECL := $d;
        :my $*METHODTYPE := $d;
        :my $*HAS_SELF := $d eq 'submethod' ?? 'partial' !! 'complete';
        :my $*DOC := $*DECLARATOR_DOCS;
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND := $*W.stub_code_object($d eq 'submethod' ?? 'Submethod' !! 'Method');
        :my $*CODE_OBJECT := $*DECLARAND;
        :my $*SIG_OBJ;
        :my %*SIG_INFO;
        :my $*BORG := {};
        {
            if $*PRECEDING_DECL_LINE < $*LINE_NO {
                $*PRECEDING_DECL_LINE := $*LINE_NO;
                $*PRECEDING_DECL := $*DECLARAND;
            }
        }
        <.attach_leading_docs>
        [
            <.newpad>
            [
            | $<specials>=[<[ ! ^ ]>?]<longname> [ '(' <multisig(1)> ')' ]? <trait>*
            | '(' <multisig(1)> ')' <trait>*
            | <sigil>'.':!s
                :dba('subscript signature')
                [
                | '(' ~ ')' <multisig(1)>
                | '[' ~ ']' <multisig(1)>
                | '{' ~ '}' <multisig(1)>
                ]:s
                <trait>*
            | <?>
            ]
            {
                $*IN_DECL := '';

                my $meta := $<specials> && ~$<specials> eq '^';
                my $invocant_type := $*W.find_symbol([
                    $<longname> && $*W.is_lexical('$?CLASS') && !$meta
                        ?? '$?CLASS'
                        !! 'Mu']);
                if $<multisig> {
                    %*SIG_INFO := $<multisig>.ast;
                    $*SIG_OBJ := $*W.create_signature_and_params($<multisig>,
                        %*SIG_INFO, $*W.cur_lexpad(), 'Any', :method,
                        :$invocant_type);
                }
                else {
                    %*SIG_INFO := hash(parameters => []);
                    $*SIG_OBJ := $*W.create_signature_and_params($/,
                        %*SIG_INFO, $*W.cur_lexpad(), 'Any', :method,
                        :$invocant_type);
                }
            }
            [
            || <onlystar>
            || <blockoid>
            ]
        ] || <.malformed('method')>
    }

    rule macro_def() {
        :my $*IN_DECL := 'macro';
        :my $*IMPLICIT := 0;
        :my $*DOC := $*DECLARATOR_DOCS;
        <.experimental('macros')>
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND := $*W.stub_code_object('Macro');
        :my $*CODE_OBJECT := $*DECLARAND;
        :my $*BORG := {};
        {
            if $*PRECEDING_DECL_LINE < $*LINE_NO {
                $*PRECEDING_DECL_LINE := $*LINE_NO;
                $*PRECEDING_DECL := $*DECLARAND;
            }
        }
        <.attach_leading_docs>
        <deflongname>?
        {
            if $<deflongname> && $<deflongname><colonpair>[0]<coloncircumfix> -> $cf {
                # It's an (potentially new) operator, circumfix, etc. that we
                # need to tweak into the grammar.
                my $category := $<deflongname><name>.Str;
                my $opname := $cf<circumfix>
                    ?? $*W.colonpair_nibble_to_str($/, $cf<circumfix><nibble>)
                    !! '';
                my $canname := $category ~ $*W.canonicalize_pair('sym', $opname);
                $/.CURSOR.add_categorical($category, $opname, $canname, $<deflongname>.ast, $*DECLARAND);
            }
        }
        <.newpad>
        [ '(' <multisig> ')' ]?
        <trait>*
        { $*IN_DECL := ''; }
        [
        || <onlystar>
        || <blockoid>
        ]
    }

    token onlystar {
        :my $*CURPAD;
        <?{ $*MULTINESS eq 'proto' }>
        '{' <.ws> '*' <.ws> '}'
        <?ENDSTMT>
        <.finishpad>
        { $*CURPAD := $*W.pop_lexpad() }
    }

    ###########################
    # Captures and Signatures #
    ###########################

    token capterm {
        '\\'
        [
        | '(' <semiarglist> ')'
        | <?before '$' | '@' | '%' | '&'> <.typed_worry('X::Worry::P5::Reference')> <termish>
        | <?before \d> <.typed_worry('X::Worry::P5::BackReference')> <termish>
        | <?before \S> <termish>
        | {} <.panic: "You can't backslash that">
        ]
    }

    rule param_sep {
        '' $<sep>=[','|':'|';;'|';'] {
            if $<sep> eq ';;' {
                $/.CURSOR.panic("Can only specify ';;' once in a signature")
                  if $*multi_invocant == 0;
                $*multi_invocant := 0;
            }
            @*seps.push($<sep>);
        }
    }

    # XXX Not really implemented yet.
    token multisig($allow_invocant = 0) {
        :my $*SCOPE := 'my';
        <signature('sig', $allow_invocant)>
    }

    token sigterm {
        :dba('signature')
        ':(' ~ ')' <fakesignature>
    }

    token fakesignature {
        <.newpad>
        <signature>
    }

    token signature($*IN_DECL = 'sig', $*ALLOW_INVOCANT = 0) {
        :my $*zone := 'posreq';
        :my $*multi_invocant := 1;
        :my @*seps := nqp::list();
        <.ws>
        [
        | <?before '-->' | ')' | ']' | '{' | ':'\s | ';;' >
        | <parameter>
        ]+ % <param_sep>
        <.ws>
        [ <?before '-->' | ')' | ']' | '{' | ':'\s | ';;' > || <.malformed('parameter')> ]
        { $*IN_DECL := ''; }
        [ '-->' <.ws> [[<typename>|<value>] <.ws> <?[ { ) ]> || <typo_typename(1)> || <.malformed('return value')>] ]?
        { $*LEFTSIGIL := '@'; }
    }

    token parameter {
        # We'll collect parameter information into a hash, then use it to
        # build up the parameter object in the action method
        :my %*PARAM_INFO;
        [
        | <type_constraint>+
            [
            | $<quant>=['**'|'*'|'+'] <param_var>
            | $<quant>=['\\'|'|'] <param_var> {
                $/.CURSOR.panic('Obsolete use of | or \\ with sigil on param ' ~ $<param_var>);
            }
            | $<quant>=['\\'|'|'|'+'] <defterm>?

            | [ <param_var> | <named_param> ] $<quant>=['?'|'!'|<?>]
            | <?>
            ]
        | $<quant>=['**'|'*'|'+'] <param_var>
        | $<quant>=['\\'|'|'] <param_var> {
            $/.CURSOR.panic('Obsolete use of | or \\ with sigil on param ' ~ $<param_var>);
        }
        | $<quant>=['\\'|'|'|'+'] <defterm>?
        | [ <param_var> | <named_param> ] $<quant>=['?'|'!'|<?>]
        | <longname>
            {
                my $name := $*W.dissect_longname($<longname>);
                $*W.throw($/, ['X', 'Parameter', 'InvalidType'],
                    :typename($name.name),
                    :suggestions($*W.suggest_typename($name.name)));
            }
        ]
        <.ws>
        <trait>*
        <post_constraint('param')>*
        [
            <default_value>
            [ <modifier=.trait> {
                self.typed_panic: "X::Parameter::AfterDefault", type => "trait", modifier => $<modifier>, default => $<default_value>
            }]?
            [ <modifier=.post_constraint('param')> {
                self.typed_panic: "X::Parameter::AfterDefault", type => "post constraint", modifier => $<modifier>, default => $<default_value>
            }]?
        ]**0..1

        # enforce zone constraints
        {
            my $kind :=
                $<named_param>                      ?? '*' !!
                $<quant> eq '?' || $<default_value> ?? '?' !!
                $<quant> eq '!'                     ?? '!' !!
                $<quant> ne '' && $<quant> ne '\\'  ?? '*' !!
                                                       '!';
            my $name := %*PARAM_INFO<variable_name> // '';
            if $kind eq '!' {
                if $*zone eq 'posopt' {
                    $/.CURSOR.typed_panic('X::Parameter::WrongOrder', misplaced => 'required', after => 'optional', parameter => $name);
                }
                elsif $*zone eq 'var' {
                    $/.CURSOR.typed_panic('X::Parameter::WrongOrder', misplaced => 'required', after => 'variadic', parameter => $name);
                }
            }
            elsif $kind eq '?' {
                if $*zone  eq 'posreq' {
                        $*zone := 'posopt';
                }
                elsif $*zone eq  'var' {
                    $/.CURSOR.typed_panic('X::Parameter::WrongOrder', misplaced => 'optional positional', after => 'variadic', parameter => $name);
                }
            }
            elsif $kind eq '*' {
                $*zone := 'var';
            }

            %*PARAM_INFO<is_multi_invocant> := $*multi_invocant;
            %*PARAM_INFO<node> := $/;
        }
    }

    token param_var {
        :dba('formal parameter')
        :my $*DOC := $*DECLARATOR_DOCS; # these get cleared later
        :my $*POD_BLOCK;
        :my $*SURROUNDING_DECL := nqp::getlexdyn('$*IN_DECL');
        <.attach_leading_docs>
        {
            my $line_no := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
            if $*PRECEDING_DECL_LINE < $line_no {
                $*PRECEDING_DECL_LINE := $line_no;
                my $par_type := $*W.find_symbol(['Parameter'], :setting-only);
                $*PRECEDING_DECL := nqp::create($par_type); # actual declarand comes later, in World::create_parameter
            }
        }
        [
        | '[' ~ ']' <signature>
        | '(' ~ ')' <signature>
        | <sigil> <twigil>?
          [
          || <?{ $<sigil>.Str eq '&' }> <?identifier> {}
             <name=.sublongname>
          || <name=.identifier>
          || <name=.decint> { $*W.throw($/, 'X::Syntax::Variable::Numeric', what => 'parameter') }
          || $<name>=[<[/!]>]
          ]?

          :dba('shape declaration')
          :my $*IN_DECL := '';
          [
          | <?before ':('>  ':'  # XXX allow fakesig parsed as subsig for the moment
          | <?before '('>         <.sorry: "Shape declaration with () is reserved;\n  please use whitespace if you meant a subsignature for unpacking,\n  or use the :() form if you meant to add signature info to the function's type">
          | <?before '['> <arrayshape=.postcircumfix>
          | <?before <[ { < « ]>> <.sorry: 'Shape declaration is not yet implemented; please use whitespace if you meant something else'>
               <postcircumfix>
          ]?
        ]
    }

    token named_param {
        :my $*GOAL := ')';
        :dba('named parameter')
        ':'
        [
        | <name=.identifier> '('
            <.ws> [ <named_param> | <param_var> ] <.ws>
            [ ')' || <.panic: 'Unable to parse named parameter; couldn\'t find right parenthesis'> ]
        | <param_var>
        ]
    }

    rule default_value {
        :my $*IN_DECL := '';
        '=' <EXPR('i=')>
    }

    token type_constraint {
        :my $*IN_DECL := '';
        [
        | <value>
        | $<value>=['-'\d+]
        | <typename>
        | where <.ws> <EXPR('i=')>
        ]
        <.ws>
    }

    rule post_constraint($*CONSTRAINT_USAGE) {
        :my $*IN_DECL := '';
        :dba('constraint')
        [
        | '[' ~ ']' <signature>
        | '(' ~ ')' <signature>
        | where <EXPR('i=')>
        ]
    }

    proto token regex_declarator { <...> }
    token regex_declarator:sym<rule> {
        <sym><.kok>
        :my %*RX;
        :my $*INTERPOLATE := 1;
        :my $*METHODTYPE := 'rule';
        :my $*IN_DECL    := 'rule';
        :my $*LINE_NO    := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        {
            %*RX<s> := 1;
            %*RX<r> := 1;
        }
        <regex_def>
    }
    token regex_declarator:sym<token> {
        <sym><.kok>
        :my %*RX;
        :my $*INTERPOLATE := 1;
        :my $*METHODTYPE := 'token';
        :my $*IN_DECL    := 'token';
        :my $*LINE_NO    := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        {
            %*RX<r> := 1;
        }
        <regex_def>
    }
    token regex_declarator:sym<regex> {
        <sym><.kok>
        :my %*RX;
        :my $*INTERPOLATE := 1;
        :my $*METHODTYPE := 'regex';
        :my $*IN_DECL    := 'regex';
        :my $*LINE_NO    := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
        <regex_def>
    }

    rule regex_def {
        :my $*CURPAD;
        :my $*HAS_SELF := 'complete';
        :my $*DOC := $*DECLARATOR_DOCS;
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND := $*W.stub_code_object('Regex');
        :my $*CODE_OBJECT := $*DECLARAND;
        {
            if $*PRECEDING_DECL_LINE < $*LINE_NO {
                $*PRECEDING_DECL_LINE := $*LINE_NO;
                $*PRECEDING_DECL := $*DECLARAND;
            }
        }
        <.attach_leading_docs>
        [
          <deflongname>?
          { if $<deflongname> { %*RX<name> := ~$<deflongname>.ast } }
          { $*IN_DECL := '' }
           <.newpad>
          [ [ ':'?'(' <signature('sig', 1)> ')' ] | <trait> ]*
          '{'
          [
          | ['*'|'<...>'|'<*>'] <?{ $*MULTINESS eq 'proto' }> $<onlystar>={1}
          | <nibble(self.quote_lang(%*RX<P5> ?? %*LANG<P5Regex> !! %*LANG<Regex>, '{', '}'))>
          ]
          '}'<!RESTRICTED><?ENDSTMT>
          { $*CURPAD := $*W.pop_lexpad() }
        ] || <.malformed('regex')>
    }

    proto token type_declarator { <...> }

    token type_declarator:sym<enum> {
        <sym><.kok>
        :my $*IN_DECL := 'enum';
        :my $*DOC := $*DECLARATOR_DOCS;
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND;
        {
            my $line_no := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
            if $*PRECEDING_DECL_LINE < $line_no {
                $*PRECEDING_DECL_LINE := $line_no;
                $*PRECEDING_DECL      := Mu; # actual declarand comes later, in Actions::type_declarator:sym<enum>
            }
        }
        <.attach_leading_docs>
        [
        | <longname>
            {
                my $longname := $*W.dissect_longname($<longname>);
                my @name := $longname.type_name_parts('enum name', :decl(1));
                if $*W.already_declared($*SCOPE, $*PACKAGE, $*W.cur_lexpad(), @name) {
                    $*W.throw($/, ['X', 'Redeclaration'],
                        symbol => $longname.name(),
                    );
                }
            }
        | <variable>
        | <?>
        ]
        { $*IN_DECL := ''; }
        <.ws>
        <trait>*
        <?[<(«]> <term> <.ws>
    }

    rule type_declarator:sym<subset> {
        <sym><.kok> :my $*IN_DECL := 'subset';
        :my $*DOC := $*DECLARATOR_DOCS;
        { $*DECLARATOR_DOCS := '' }
        :my $*POD_BLOCK;
        :my $*DECLARAND;
        {
            my $line_no := HLL::Compiler.lineof(self.orig(), self.from(), :cache(1));
            if $*PRECEDING_DECL_LINE < $line_no {
                $*PRECEDING_DECL_LINE := $line_no;
                $*PRECEDING_DECL      := Mu; # actual declarand comes later, in Actions::type_declarator:sym<subset>
            }
        }
        <.attach_leading_docs>
        [
            [
                [
                    <longname>
                    {
                        my $longname := $*W.dissect_longname($<longname>);
                        my @name := $longname.type_name_parts('subset name', :decl(1));
                        if $*W.already_declared($*SCOPE, $*PACKAGE, $*W.cur_lexpad(), @name) {
                            $*W.throw($/, ['X', 'Redeclaration'],
                                symbol => $longname.name(),
                            );
                        }
                    }
                ]?
                { $*IN_DECL := '' }
                <trait>*
                [ where <EXPR('e=')> ]?
            ]
            || <.malformed('subset')>
        ]
    }

    token type_declarator:sym<constant> {
        :my $*IN_DECL := 'constant';
        <sym><.kok>

        [
        | '\\'? <defterm>
        | <variable> { $¢.add_variable(~$<variable>) } # for new &infix:<foo> synonyms
        | <?>
        ]
        { $*IN_DECL := ''; }
        <.ws>

        <trait>*

        { $*W.push_lexpad($/) }
        [
        || <initializer>
        || <.missing: "initializer on constant declaration">
        ]

        <.cheat_heredoc>?
    }

    proto token initializer { <...> }
    token initializer:sym<=> {
        <sym>
        [
            <.ws>
            [
            || <?{ $*LEFTSIGIL eq '$' }> <EXPR('i<=')>
            || <EXPR('e=')>
            ]
            || <.malformed: 'initializer'>
        ]
    }
    token initializer:sym<:=> {
        <sym> [ <.ws> <EXPR('e=')> || <.malformed: 'binding'> ]
    }
    token initializer:sym<::=> {
        <sym> [ <.ws> <EXPR('e=')> <.NYI('"::="')> || <.malformed: 'binding'> ]
    }
    token initializer:sym<.=> {
        <sym> [ <.ws> <dottyopish> || <.malformed: 'mutator method call'> ]
    }

    rule trait {
        :my $*IN_DECL := '';
        <trait_mod>
    }

    proto rule trait_mod { <...> }
    rule trait_mod:sym<is> {
        :my %*MYSTERY;
        <sym> [ [<longname><circumfix>**0..1] || <.panic: 'Invalid name'> ]
        <.explain_mystery> <.cry_sorrows>
        {
            if $<circumfix> && nqp::substr(self.orig, $<longname>.to, 1) eq '{' {
                $*BORG<block> := $<circumfix>[0];
                $*BORG<name> := 'is ' ~ $<longname>;
            }
        }
    }
    rule trait_mod:sym<hides>   { <sym> [ <typename> || <.bad_trait_typename>] }
    rule trait_mod:sym<does>    { <sym> [ <typename> || <.bad_trait_typename>] }
    rule trait_mod:sym<will>    { <sym> [ <identifier> || <.panic: 'Invalid name'>] <pblock(1)> }
    rule trait_mod:sym<of>      { <sym> [ <typename> || <.bad_trait_typename>] }
    rule trait_mod:sym<as>      { <sym> [ <typename> || <.bad_trait_typename>] }
    rule trait_mod:sym<returns> { <sym> [ <typename> || <.bad_trait_typename>] }
    rule trait_mod:sym<handles> { <sym> [ <term> || <.panic: 'Invalid term'>] }

    token bad_trait_typename {
        || <longname> {
                my $name := $*W.dissect_longname($<longname>);
                $*W.throw($/, ['X', 'InvalidType'],
                    :typename($name.name),
                    :suggestions($*W.suggest_typename($name.name)));
            }
        || <.malformed: 'trait'>
    }

    ## Terms

    proto token term { <...> }

    token term:sym<self> {
        <sym> <.end_keyword>
        {
            $*HAS_SELF || self.typed_sorry('X::Syntax::Self::WithoutObject')
        }
    }

    token term:sym<now> { <sym> <.tok> }

    token term:sym<time> { <sym> <.tok> }

    token term:sym<empty_set> { "∅" <!before <[ \( \\ ' \- ]> || \h* '=>'> }

    token term:sym<rand> {
        <sym> »
        [ <?before '('? \h* [\d|'$']> <.obs('rand(N)', 'N.rand for Num or (^N).pick for Int result')> ]?
        [ <?before '()'> <.obs('rand()', 'rand')> ]?
        <.end_keyword>
    }

    token term:sym<...> { [<sym>|'…'] <args> }
    token term:sym<???> { <sym> <args> }
    token term:sym<!!!> { <sym> <args> }

    token term:sym<identifier> {
        :my $pos;
        <identifier> <!{ $*W.is_type([~$<identifier>]) }> <?before <.unsp>|'('> <![:]>
        { $pos := $/.CURSOR.pos }
        <args(1)>
        {
            if !$<args><invocant> {
                self.add_mystery($<identifier>, $<args>.from, nqp::substr(~$<args>, 0, 1));
                if $*BORG<block> {
                    unless $*BORG<name> {
                        $*BORG<name> := ~$<identifier>;
                    }
                }
            }
        }
    }

    token term:sym<nqp::op> {
        'nqp::' $<op>=[\w+] <args>?
    }

    token term:sym<nqp::const> {
        'nqp::const::' $<const>=[\w+]
    }

    my %deftrap := nqp::hash(
        'say', 1, 'print', 1, 'abs', 1, 'chomp', 1, 'chop', 1, 'chr', 1, 'cos', 1,
        'defined', 1, 'exp', 1, 'lc', 1, 'log', 1, 'mkdir', 1, 'ord', 1, 'reverse', 1,
        'rmdir', 1, 'sin', 1, 'split', 1, 'sqrt', 1, 'uc', 1, 'unlink', 1, 'WHAT', 2,
        'WHICH', 2, 'WHERE', 2, 'HOW', 2, 'WHENCE', 2, 'WHO', 2, 'VAR', 2, 'any', 2,
        'all', 2, 'none', 2, 'one', 2, 'set', 2, 'bag', 2, 'tclc', 2, 'wordcase', 2,
    );

    token term:sym<name> {
        <longname>
        :my %colonpairs;
        :my $*longname;
        :my $pos;
        :my $*IN_RETURN;
        :my $is_type := 0;
        {
            $*longname := $*W.dissect_longname($<longname>);
            $pos := $/.CURSOR.pos;
            $*IN_RETURN := $<longname>.Str eq 'return';
            $is_type := !$*longname.get_who && $*W.is_type($*longname.components());
        }
        [
        ||  <?{ nqp::eqat($<longname>.Str, '::', 0) || $*W.is_name($*longname.components()) }>
            <.unsp>?
            [
                <?[[]> <?{ $is_type }>
                :dba('type parameter') '[' ~ ']' <arglist>
            ]?
            <.unsp>?
            [
                <?[{]> <?{ $is_type }>
                <whence=.postcircumfix> <.NYI('Autovivifying object closures')>
            ]?
            <.unsp>?
            [
                <?[(]> <?{ $is_type }>
                '(' <.ws> [
                    || <accept=.typename> <!{ nqp::isconcrete($<accept>.ast) }>
                    || $<accept_any>=<?>
                ] <.ws> ')'
            ]?
            {
                for $<longname><colonpair> {
                    if $_<identifier> {
                        my $name := $_<identifier>.Str;
                        if $name eq 'D' || $name eq 'U' || $name eq '_' {
                            %colonpairs{$name} := 1;
                        }
                        else {
                            $*W.throw($/, ['X', 'InvalidTypeSmiley'], :$name)
                        }
                    }
                }
            }
            [<?{ %colonpairs }> <colonpairs=.AS_MATCH(%colonpairs)>]?
        || <args(1)>
            {
                if !$<args><invocant> {
                    my $name := ~$<longname>;
                    if $*BORG<block> {
                        unless $*BORG<name> {
                            $*BORG<name> := $*BORG<name> // $name;
                        }
                    }
                    my $nextch := nqp::substr($/.CURSOR.orig, $/.CURSOR.pos, 1) || ' ';
                    if %deftrap{$name} {
                        my $al := $<args><arglist>;
                        my int $ok := 0;
                        $ok := 1 unless $al<EXPR> eq '';
                        $ok := 1 if $<args><semiarglist>;
                        unless $ok {
                            my $trap := %deftrap{$name};
                            if nqp::index('<[{', $nextch) >= 0 {
                                $/.CURSOR.typed_panic('X::Syntax::Confused', reason => "Use of non-subscript brackets after \"$name\" where postfix is expected; please use whitespace before any arguments")
                            }
                            elsif nqp::index('$@%&+-/*', $nextch) >= 0 {
                                $/.CURSOR.typed_panic('X::Syntax::Confused', reason => "A list operator such as \"$name\" must have whitespace before its arguments (or use parens)")
                            }
                            else {
                                my $missing := $/.CURSOR.terminator() || $/.CURSOR.infixish();
                                $/.CURSOR.'!clear_highwater'();  # don't have suppose
                                my $orry := $missing ?? "sorry" !! "worry";
                                if $trap == 1 {        # probably misused P5ism
                                    $<longname>.CURSOR."{$orry}obs"("bare \"$name\"", ".$name if you meant \$_, or use an explicit invocant or argument, or use &$name to refer to the function as a noun");
                                }
                                elsif $trap == 2 {        # probably misused P6ism
                                    $<longname>.CURSOR."$orry"("Function \"$name\" may not be called without arguments (please use () or whitespace to denote arguments, or &$name to refer to the function as a noun)");
                                }
                                $<longname>.CURSOR.sorry("Argument to \"$name\" seems to be malformed") if $orry eq 'worry';
                            }
                        }
                    }
                }
            }
        ]
    }

    token term:sym<dotty> { <dotty> { self.mark_variable_used('$_') } }

    token term:sym<capterm> { <capterm> }

    token term:sym<onlystar> {
        '{*}' <?ENDSTMT>
        [ <?{ $*IN_PROTO }> || <.panic: '{*} may only appear in proto'> ]
    }

    token args($*INVOCANT_OK = 0) {
        :my $*INVOCANT;
        :my $*GOAL := '';
        :my $*FAKE_INFIX_FOUND := 0;
        :dba('argument list')
        [
        | '(' ~ ')' <semiarglist>
        | <.unsp> '(' ~ ')' <semiarglist>
        | [ \s <arglist> ]
        | <?>
        ]
    }

    token semiarglist {
        <arglist>+ % ';'
        <.ws>
    }

    token arglist {
        :my $*GOAL := 'endargs';
        :my $*QSIGIL := '';
        :my $*ARG_FLAT_OK := 1;
        <.ws>
        :dba('argument list')
        [
        | <?stdstopper>
        | <EXPR('e=')>
        | <?>
        ]
    }

    proto token value { <...> }
    token value:sym<quote>  { <quote> }
    token value:sym<number> { <number> }
    token value:sym<version> { <version> }

    proto token number { <...> }
    token number:sym<numish>   { <numish> }

    token signed-number { <sign> <number> }

    token numish {
        [
        | 'NaN' >>
        | <integer>
        | <dec_number>
        | <rad_number>
        | <rat_number>
        | <complex_number>
        | 'Inf' >>
        | '+Inf' >>
        | '-Inf' >>
        | <?{ nqp::existskey(nqp::backendconfig(), 'moarlib') }> <unum=:No+:Nl>
        ]
    }

    token dec_number {
        :dba('decimal number')
        [
        | $<coeff> = [               '.' <frac=.decint> ] <escale>?
        | $<coeff> = [ <int=.decint> '.' <frac=.decint> ] <escale>?
        | $<coeff> = [ <int=.decint>                    ] <escale>
        ]
    }

    token signed-integer { <sign> <integer> }

    token integer {
        [
        | 0 [ b '_'? <VALUE=binint>
            | o '_'? <VALUE=octint>
            | x '_'? <VALUE=hexint>
            | d '_'? <VALUE=decint>
            | <VALUE=decint>
                <!!{ $/.CURSOR.typed_worry('X::Worry::P5::LeadingZero', value => ~$<VALUE>) }>
            ]
        | <VALUE=decint>
        ]
        <!!before ['.' <?before \s | ',' | '=' | <terminator> | $ > <.typed_sorry: 'X::Syntax::Number::IllegalDecimal'>]? >
        [ <?before '_' '_'+\d> <.sorry: "Only isolated underscores are allowed inside numbers"> ]?
    }

    token rad_number {
        ':' $<radix> = [\d+] <.unsp>?
        {}           # don't recurse in lexer
        :dba('number in radix notation')
        [
        || '<'
                $<ohradix> = [ '0x' <?{ +$<radix> < 34 }> | '0o' <?{ +$<radix> < 25 }> | '0d' <?{ +$<radix> < 14 }> | '0b' <?{ +$<radix> < 12 }> ]**0..1
                $<intpart> = [ [\d | <[ a..z A..Z ａ..ｚ Ａ..Ｚ ]>]+ [ _ [\d | <[ a..z A..Z ａ..ｚ Ａ..Ｚ ]>]+ ]* ]
                $<fracpart> = [ '.' [\d | <[ a..z A..Z ａ..ｚ Ａ..Ｚ ]>]+ [ _ [\d | <[ a..z A..Z ａ..ｚ Ａ..Ｚ ]>]+ ]* ]**0..1
                [ '*' <base=.radint> '**' <exp=.radint> ]**0..1
           '>'
        || <?[[]> <bracket=circumfix>
        || <?[(]> <circumfix>
        || <.malformed: 'radix number'>
        ]
    }

    token radint {
        [
        | <integer>
        # | <?before ':'\d> <rad_number> <?{
        #                         defined $<rad_number><intpart>
        #                         and
        #                         not defined $<rad_number><fracpart>
        #                     }>
        ]
    }

    token escale { <[Ee]> <sign> <decint> }

    token sign { '+' | '-' | '' }

    token rat_number { '<' <bare_rat_number> '>' }
    token bare_rat_number { <?before <[\-+0..9<>:boxd]>+? '/'> <nu=.signed-integer> '/' <de=integer> }

    token complex_number { '<' <bare_complex_number> '>' }
    token bare_complex_number { <?before <[\-+0..9<>:.eEboxdInfNa\\]>+? 'i'> <re=.signed-number> <?[\-+]> <im=.signed-number> \\? 'i' }

    token typename {
        :my %colonpairs;
        [
        | '::?'<identifier> <colonpair>*    # parse ::?CLASS as special case
        | <longname>
          <?{
            my $longname := $*W.dissect_longname($<longname>);
            nqp::eqat(~$<longname>, '::', 0) ??
                1 !! # ::T introduces a type, so always is one
                $*W.is_name($longname.type_name_parts('type name'))
          }>
        ]
        # parametric/coercion type?
        <.unsp>? [ <?[[]> '[' ~ ']' <arglist> ]?
        <.unsp>? [ <?before '{'> <whence=.postcircumfix> <.NYI('Autovivifying object closures')> ]?
        <.unsp>? [ <?[(]> '(' ~ ')' [<.ws> [<accept=.typename> || $<accept_any>=<?>] <.ws>] ]?
        [<.ws> 'of' <.ws> <typename> ]?
        {
            for ($<longname> ?? $<longname><colonpair> !! $<colonpair>) {
                if $_<identifier> {
                    my $name := $_<identifier>.Str;
                    if $name eq 'D' || $name eq 'U' || $name eq '_' {
                        %colonpairs{$name} := 1;
                    }
                    else {
                        $*W.throw($/, ['X', 'InvalidTypeSmiley'], :$name)
                    }
                }
            }
        }
        [<?{ %colonpairs }> <colonpairs=.AS_MATCH(%colonpairs)>]?
    }

    token typo_typename($panic = 0) {
        <longname>
        {
          my $longname := $*W.dissect_longname($<longname>);
          my @suggestions := $*W.suggest_typename($longname.name);
          my $method := $panic ?? 'typed_panic' !! 'typed_sorry';
          $/.CURSOR."$method"('X::Undeclared',
                    what => "Type",
                    symbol => $longname.name(),
                    suggestions => @suggestions);
        }
    }


    token quotepair($*purpose = 'quoteadverb') {
        :my $*key;
        :my $*value;
        ':'
        :dba('colon pair (restricted)')
        [
        | '!' <identifier> [ <?[(]> <.sorry('Argument not allowed on negated pair')> ]?
            { $*key := ~$<identifier>; $*value := 0; }
        | <identifier>
            { $*key := ~$<identifier> }
            [
            || <?[(]> <circumfix> { $*value := $<circumfix>.ast; }
            || { $*value := 1; }
            ]
        | (\d+) <identifier>
            [ <?[(]> <.circumfix> <.sorry('2nd argument not allowed on pair')> ]?
            { $*key := ~$<identifier>; $*value := +~$/[0] }
        ]
    }

    token rx_adverbs {
        [
            <quotepair('rxadverb')> <.ws>
            :my $*ADVERB;
            { $*ADVERB := $<quotepair>[-1] }
            <.setup_quotepair>
        ]*
    }

    token qok($x) {
        » <![(]>
        [ <?[:]> || <!{ my $n := ~$x; $*W.is_name([$n]) || $*W.is_name(['&' ~ $n]) }> ]
        [ \s* '#' <.panic: "# not allowed as delimiter"> ]?
        <.ws>
    }

    proto token quote_mod   {*}
    token quote_mod:sym<w>  { <sym> }
    token quote_mod:sym<ww> { <sym> }
    # XXX uncomment this when it's implemented
    #token quote_mod:sym<p>  { <sym> }
    token quote_mod:sym<x>  { <sym> }
    token quote_mod:sym<to> { <sym> }
    token quote_mod:sym<s>  { <sym> }
    token quote_mod:sym<a>  { <sym> }
    token quote_mod:sym<h>  { <sym> }
    token quote_mod:sym<f>  { <sym> }
    token quote_mod:sym<c>  { <sym> }
    token quote_mod:sym<b>  { <sym> }

    proto token quote { <...> }
    token quote:sym<apos>  { :dba('single quotes') "'" ~ "'" <nibble(self.quote_lang(%*LANG<Quote>, "'", "'", ['q']))> }
    token quote:sym<sapos> { :dba('smart single quotes') "‘" ~ "’" <nibble(self.quote_lang(%*LANG<Quote>, "‘", "’", ['q']))> }
    token quote:sym<lapos> { :dba('low smart single quotes') "‚" ~ <[’‘]> <nibble(self.quote_lang(%*LANG<Quote>, "‚", ["’","‘"], ['q']))> }
    token quote:sym<hapos> { :dba('high smart single quotes') "’" ~ <[’‘]> <nibble(self.quote_lang(%*LANG<Quote>, "’", ["’","‘"], ['q']))> }
    token quote:sym<dblq>  { :dba('double quotes') '"' ~ '"' <nibble(self.quote_lang(%*LANG<Quote>, '"', '"', ['qq']))> }
    token quote:sym<sdblq> { :dba('smart double quotes') '“' ~ '”' <nibble(self.quote_lang(%*LANG<Quote>, '“', '”', ['qq']))> }
    token quote:sym<ldblq> { :dba('low smart double quotes') '„' ~ <[”“]> <nibble(self.quote_lang(%*LANG<Quote>, '„', ['”','“'], ['qq']))> }
    token quote:sym<hdblq> { :dba('high smart double quotes') '”' ~ <[”“]> <nibble(self.quote_lang(%*LANG<Quote>, '”', ['”','“'], ['qq']))> }
    token quote:sym<crnr>  { :dba('corner quotes') '｢' ~ '｣' <nibble(self.quote_lang(%*LANG<Quote>, '｢', '｣'))> }
    token quote:sym<q> {
        :my $qm;
        'q'
        [
        | <quote_mod> {} <.qok($/)> { $qm := $<quote_mod>.Str } <quibble(%*LANG<Quote>, 'q', $qm)>
        | {} <.qok($/)> <quibble(%*LANG<Quote>, 'q')>
        ]
    }
    token quote:sym<qq> {
        :my $qm;
        'qq'
        [
        | <quote_mod> { $qm := $<quote_mod>.Str } <.qok($/)> <quibble(%*LANG<Quote>, 'qq', $qm)>
        | {} <.qok($/)> <quibble(%*LANG<Quote>, 'qq')>
        ]
    }
    token quote:sym<Q> {
        :my $qm;
        'Q'
        [
        | <quote_mod> { $qm := $<quote_mod>.Str } <.qok($/)> <quibble(%*LANG<Quote>, $qm)>
        | {} <.qok($/)> <quibble(%*LANG<Quote>)>
        ]
    }

    token quote:sym</null/> { '/' \s* '/' <.typed_panic: "X::Syntax::Regex::NullRegex"> }
    token quote:sym</ />  {
        :my %*RX;
        :my $*INTERPOLATE := 1;
        '/' <nibble(self.quote_lang(%*LANG<Regex>, '/', '/'))> [ '/' || <.panic: "Unable to parse regex; couldn't find final '/'"> ]
        <.old_rx_mods>?
    }
    token quote:sym<rx>   {
        <sym>
        :my %*RX;
        :my $*INTERPOLATE := 1;
        {} <.qok($/)>
        <rx_adverbs>
        <quibble(%*RX<P5> ?? %*LANG<P5Regex> !! %*LANG<Regex>)>
        <!old_rx_mods>
    }

    token quote:sym<m> {
        <sym> (s)**0..1
        :my %*RX;
        :my $*INTERPOLATE := 1;
        { %*RX<s> := 1 if $/[0] }
        <.qok($/)>
        <rx_adverbs>
        <quibble(%*RX<P5> ?? %*LANG<P5Regex> !! %*LANG<Regex>)>
        <!old_rx_mods>
    }

    token quote:sym<qr> {
        <sym> {} <.qok($/)> <.obs('qr for regex quoting', 'rx//')>
    }

    token setup_quotepair { '' }

    token sibble($l, $lang2, @lang2tweaks?) {
        :my $lang;
        :my $start;
        :my $stop;
        <babble($l)>
        { my $B := $<babble><B>.ast; $lang := $B[0]; $start := $B[1]; $stop := $B[2]; }

        $start <left=.nibble($lang)> [ $stop || <.panic("Couldn't find terminator $stop")> ]
        [ <?{ $start ne $stop }>
            <.ws>
            [ <?[ \[ \{ \( \< ]> <.obs('brackets around replacement', 'assignment syntax')> ]?
            [ <infixish> || <.missing: "assignment operator"> ]
            [ <?{ $<infixish>.Str eq '=' || $<infixish><infix_postfix_meta_operator> }> || <.malformed: "assignment operator"> ]
            <.ws>
            [ <right=.EXPR('i')> || <.panic: "Assignment operator missing its expression"> ]
        ||
            { $lang := self.quote_lang($lang2, $stop, $stop, @lang2tweaks); }
            <right=.nibble($lang)> $stop || <.panic("Malformed replacement part; couldn't find final $stop")>
        ]
    }

    token quote:sym<s> {
        <sym=[Ss]> (s)**0..1
        :my %*RX;
        :my $*INTERPOLATE := 1;
        {
            %*RX<s> := 1 if $/[0]
        }
        <.qok($/)>
        <rx_adverbs>
        <sibble(%*RX<P5> ?? %*LANG<P5Regex> !! %*LANG<Regex>, %*LANG<Quote>, ['qq'])>
        [ <?{ $<sibble><infixish> }> || <.old_rx_mods>? ]
    }

    token tribble ($l, $lang2 = $l, @lang2tweaks?) {
        :my $lang;
        :my $start;
        :my $stop;
        :my $*CCSTATE := '';
        <babble($l, @lang2tweaks)>
        { my $B := $<babble><B>.ast; $lang := $B[0]; $start := $B[1]; $stop := $B[2]; }

        $start <left=.nibble($lang)> [ $stop || <.panic: "Couldn't find terminator $stop"> ]
        { $*CCSTATE := ''; }
        [ <?{ $start ne $stop }>
            $start <right=.nibble($lang)> [ $stop || { $/.CURSOR.panic("Couldn't find terminator $stop") } ]
        ||
            { $lang := self.quote_lang($lang2, $stop, $stop, @lang2tweaks); }
            <right=.nibble($lang)> $stop || <.panic("Malformed replacement part; couldn't find final $stop")>
        ]
    }

    token quote:sym<tr> {
        <sym>
        :my %*RX;
        :my $*INTERPOLATE := 1;
        {} <.qok($/)>
        <rx_adverbs>
        <tribble(%*LANG<Quote>, %*LANG<Quote>, ['cc'])>
        <.old_rx_mods>?
    }

    token quote:sym<y> {
        <sym>
        <?before \h*\W>
        {} <.qok($/)>
        <.obs('y///','tr///')>
    }

    token old_rx_mods {
        (<[ i g s m x c e ]>)
        {
            my $m := $/[0].Str;
            if    $m eq 'i' { $/.CURSOR.obs('/i',':i');                                   }
            elsif $m eq 'g' { $/.CURSOR.obs('/g',':g');                                   }
            elsif $m eq 'm' { $/.CURSOR.obs('/m','^^ and $$ anchors');                    }
            elsif $m eq 's' { $/.CURSOR.obs('/s','. or \N');                              }
            elsif $m eq 'x' { $/.CURSOR.obs('/x','normal default whitespace');            }
            elsif $m eq 'c' { $/.CURSOR.obs('/c',':c or :p');                             }
            elsif $m eq 'e' { $/.CURSOR.obs('/e','interpolated {...} or s{} = ... form'); }
            else            { $/.CURSOR.obs('suffix regex modifiers','prefix adverbs');   }
        }
    }

    token quote:sym<quasi> {
        <sym> <.ws> <![(]>
        :my $*IN_QUASI := 1;
        :my @*UNQUOTE_ASTS := [];
        <.experimental('macros')>
        <block>
    }

    # XXX remove SEQ for xmas?
    token circumfix:sym<SEQ( )> { 'SEQ(' <.panic: "Use of unsupported SEQ macro; please change to STATEMENT_LIST"> }
    token circumfix:sym<STATEMENT_LIST( )> { :dba('statement list') 'STATEMENT_LIST(' ~ ')' <sequence> }

    token circumfix:sym<( )> {
        :my $*FAKE_INFIX_FOUND := 0;
        :dba('parenthesized expression')
        '(' ~ ')' <semilist>
    }
    token circumfix:sym<[ ]> { :dba('array composer') '[' ~ ']' <semilist> }
    token circumfix:sym<ang> {
        :dba('quote words')
        '<' ~ '>'
        [
            [ <?before 'STDIN>' > <.obs('<STDIN>', '$*IN.lines (or add whitespace to suppress warning)')> ]?
            [ <?[>]> <.obs('<>', 'lines() to read input, (\'\') to represent a null string or () to represent an empty list')> ]?
            <nibble(self.quote_lang(%*LANG<Quote>, "<", ">", ['q', 'w', 'v']))>
        ]
    }
    token circumfix:sym«<< >>» { :dba('shell-quote words') '<<' ~ '>>' <nibble(self.quote_lang(%*LANG<Quote>, "<<", ">>", ['qq', 'ww', 'v']))> }
    token circumfix:sym<« »> { :dba('shell-quote words') '«' ~ '»' <nibble(self.quote_lang(%*LANG<Quote>, "«", "»", ['qq', 'ww', 'v']))> }
    token circumfix:sym<{ }> {
        :my $*FAKE_INFIX_FOUND := 0;
        <?[{]> <pblock(1)>
        {
            $*BORG<block> := $<pblock>
        }
    }

    ## Operators

    INIT {
        Perl6::Grammar.O(':prec<y=>, :assoc<unary>, :dba<methodcall>, :fiddly<1>', '%methodcall');
        Perl6::Grammar.O(':prec<x=>, :assoc<unary>, :dba<autoincrement>', '%autoincrement');
        Perl6::Grammar.O(':prec<w=>, :assoc<right>, :dba<exponentiation>', '%exponentiation');
        Perl6::Grammar.O(':prec<v=>, :assoc<unary>, :dba<symbolic unary>', '%symbolic_unary');
        Perl6::Grammar.O(':prec<v=>, :assoc<left>, :dba<dotty infix>, :nextterm<dottyopish>, :sub<z=>, :fiddly<1>', '%dottyinfix');
        Perl6::Grammar.O(':prec<u=>, :assoc<left>, :dba<multiplicative>',  '%multiplicative');
        Perl6::Grammar.O(':prec<t=>, :assoc<left>, :dba<additive>',  '%additive');
        Perl6::Grammar.O(':prec<s=>, :assoc<left>, :dba<replication>', '%replication');
        Perl6::Grammar.O(':prec<s=>, :assoc<left>, :dba<replication> :thunky<t.>', '%replication_xx');
        Perl6::Grammar.O(':prec<r=>, :assoc<left>, :dba<concatenation>',  '%concatenation');
        Perl6::Grammar.O(':prec<q=>, :assoc<list>, :dba<junctive and>', '%junctive_and');
        Perl6::Grammar.O(':prec<p=>, :assoc<list>, :dba<junctive or>', '%junctive_or');
        Perl6::Grammar.O(':prec<o=>, :assoc<unary>, :dba<named unary>', '%named_unary');
        Perl6::Grammar.O(':prec<n=>, :assoc<non>, :dba<structural infix>, :diffy<1>',  '%structural');
        Perl6::Grammar.O(':prec<m=>, :assoc<left>, :dba<chaining>, :iffy<1>, :diffy<1> :pasttype<chain>',  '%chaining');
        Perl6::Grammar.O(':prec<l=>, :assoc<left>, :dba<tight and>, :thunky<.t>',  '%tight_and');
        Perl6::Grammar.O(':prec<k=>, :assoc<list>, :dba<tight or>, :thunky<.t>',  '%tight_or');
        Perl6::Grammar.O(':prec<k=>, :assoc<list>, :dba<tight or>',  '%tight_or_minmax');
        Perl6::Grammar.O(':prec<j=>, :assoc<right>, :dba<conditional>, :fiddly<1>, :thunky<.tt>', '%conditional');
        Perl6::Grammar.O(':prec<j=>, :assoc<right>, :dba<conditional>, :fiddly<1>, :thunky<tt>', '%conditional_ff');
        Perl6::Grammar.O(':prec<i=>, :assoc<right>, :dba<item assignment>', '%item_assignment');
        Perl6::Grammar.O(':prec<i=>, :assoc<right>, :dba<list assignment>, :sub<e=>, :fiddly<1>', '%list_assignment');
        Perl6::Grammar.O(':prec<h=>, :assoc<unary>, :dba<loose unary>', '%loose_unary');
        Perl6::Grammar.O(':prec<g=>, :assoc<list>, :dba<comma>, :nextterm<nulltermish>, :fiddly<1>',  '%comma');
        Perl6::Grammar.O(':prec<f=>, :assoc<list>, :dba<list infix>',  '%list_infix');
        Perl6::Grammar.O(':prec<e=>, :assoc<right>, :dba<list prefix>', '%list_prefix');
        Perl6::Grammar.O(':prec<d=>, :assoc<left>, :dba<loose and>, :thunky<.t>',  '%loose_and');
        Perl6::Grammar.O(':prec<d=>, :assoc<left>, :dba<loose and>, :thunky<.b>',  '%loose_andthen');
        Perl6::Grammar.O(':prec<c=>, :assoc<list>, :dba<loose or>, :thunky<.t>',  '%loose_or');
        Perl6::Grammar.O(':prec<c=>, :assoc<list>, :dba<loose or>, :thunky<.b>',  '%loose_orelse');
        Perl6::Grammar.O(':prec<b=>, :assoc<list>, :dba<sequencer>',  '%sequencer');
    }

    token termish {
        :my $*SCOPE := "";
        :my $*MULTINESS := "";
        :my $*OFTYPE;
        :my $*VAR;
        :my $orig_arg_flat_ok := $*ARG_FLAT_OK;
        :dba('term')
        [
        ||  [
            | <prefixish>+ [ <.arg_flat_nok> <term> || {} <.panic("Prefix " ~ $<prefixish>[-1].Str ~ " requires an argument, but no valid term found")> ]
            | <.arg_flat_nok> <term>
            ]
        || <!{ $*QSIGIL }> <?before <infixish> {
            $/.CURSOR.typed_panic('X::Syntax::InfixInTermPosition', infix => ~$<infixish>); } >
        || <!>
        ]
        :dba('postfix')
        [
        || <?{ $*QSIGIL }>
            [
            || <?{ $*QSIGIL eq '$' }> [ <postfixish>+! <?{ bracket_ending($<postfixish>) }> ]**0..1
            ||                          <postfixish>+! <?{ bracket_ending($<postfixish>) }>
            || { $*VAR := 0 } <!>
            ]
        || <!{ $*QSIGIL }> <postfixish>*
        ]
        { self.check_variable($*VAR) if $*VAR; $*ARG_FLAT_OK := $orig_arg_flat_ok; }
    }

    token arg_flat_nok {
        <!{ $*ARG_FLAT_OK := 0 }>
    }

    sub bracket_ending($matches) {
        my $check     := $matches[+$matches - 1];
        my str $str   := $check.Str;
        my $last  := nqp::substr($str, nqp::chars($check) - 1, 1);
        $last eq ')' || $last eq '}' || $last eq ']' || $last eq '>'
    }

    method EXPR(str $preclim = '') {
        # Override this so we can set $*LEFTSIGIL.
        my $*LEFTSIGIL := '';
        my $*IN_RETURN := 0;
        nqp::findmethod(HLL::Grammar, 'EXPR')(self, $preclim, :noinfix($preclim eq 'y='));
    }

    token prefixish {
        :dba('prefix')
        [
        | <OPER=prefix>
        | <OPER=prefix_circumfix_meta_operator>
        ]
        <prefix_postfix_meta_operator>**0..1
        <.ws>
    }

    token infixish($in_meta = nqp::getlexdyn('$*IN_META')) {
        :my $*IN_META := $in_meta;
        :my $*OPER;
        <!stdstopper>
        <!infixstopper>
        :dba('infix')
        [
        | <!{ $*IN_REDUCE }> <colonpair> <fake_infix> { $*OPER := $<fake_infix> }
        |   [
            | :dba('bracketed infix') '[' ~ ']' <infixish('[]')> { $*OPER := $<infixish><OPER> }
                # XXX Gets false positives.
                #[ <!before '='> { self.worry("Useless use of [] around infix op") unless $*IN_META; } ]?
            | :dba('infixed function') <?before '[&' <twigil>? [<alpha>|'('] > '[' ~ ']' <variable>
                {
                    $<variable><O> := nqp::hash('prec', 't=', 'assoc', 'left', 'dba', 'additive') unless $<variable><O>;
                    $*OPER := $<variable>;
                    self.check_variable($<variable>)
                }
            | <infix_circumfix_meta_operator> { $*OPER := $<infix_circumfix_meta_operator> }
            | <infix_prefix_meta_operator> { $*OPER := $<infix_prefix_meta_operator> }
            | <infix> { $*OPER := $<infix> }
            | <?{ $*IN_META ~~ /^[ '[]' | 'hyper' | 'HYPER' | 'R' | 'S' ]$/ && !$*IN_REDUCE }> <.missing("infix inside " ~ $*IN_META)>
            ]
            [ <?before '='> <infix_postfix_meta_operator> { $*OPER := $<infix_postfix_meta_operator> }
            ]?
        ]
        <OPER=.AS_MATCH($*OPER)>
    }

    token fake_infix {
        <O('%item_assignment, :assoc<unary>, :fake<1>, :dba<adverb>')>
        { $*FAKE_INFIX_FOUND := 1 }
    }

    regex infixstopper {
        :dba('infix stopper')
        [
        | <?before '!!'> <?{ $*GOAL eq '!!' }>
        | <?before '{' | <lambda> > <?MARKED('ws')> <?{ $*GOAL eq '{' || $*GOAL eq 'endargs' }>
        ]
    }

    token postfixish {
        <!stdstopper>

        # last whitespace didn't end here
        <?{
            my $c := $/.CURSOR;
            my $marked := $c.MARKED('ws');
            !$marked || $marked.from == $c.pos;
        }>

        [ <!{ $*QSIGIL }> [ <.unsp> | '\\' ] ]?

        :dba('postfix')
        [ ['.' <.unsp>?]? <postfix_prefix_meta_operator> <.unsp>?]**0..1
        [
        | <OPER=postfix>
        | '.' <?before \W> <OPER=postfix>  ## dotted form of postfix operator (non-wordy only)
        | <OPER=postcircumfix>
        | '.' <?[ [ { < ]> <OPER=postcircumfix>
        | <OPER=dotty>
        | <OPER=privop>
        | <?{ $<postfix_prefix_meta_operator> && !$*QSIGIL }>
            [
            || <?space> <.missing: "postfix">
            || <?alpha> <.missing: "dot on method call">
            || <.malformed: "postfix">
            ]
        ]
        { $*LEFTSIGIL := '@'; }
    }

    token postop {
        | <postfix>         $<O> = {$<postfix><O>} $<sym> = {$<postfix><sym>}
        | <postcircumfix>   $<O> = {$<postcircumfix><O>} $<sym> = {$<postcircumfix><sym>}
    }

    proto token prefix_circumfix_meta_operator { <...> }

    proto token infix_postfix_meta_operator { <...> }

    proto token infix_prefix_meta_operator { <...> }

    proto token infix_circumfix_meta_operator { <...> }

    proto token postfix_prefix_meta_operator { <...> }

    proto token prefix_postfix_meta_operator { <...> }

    method can_meta($op, $meta, $reason = "fiddly") {
        if nqp::eqat($op<OPER><O>{$reason}, '1', 0) {
            self.typed_panic: "X::Syntax::CannotMeta", :$meta, operator => ~$op<OPER><sym>, dba => ~$op<OPER><O><dba>, reason => "too $reason";
        }
        self;
    }

    regex term:sym<reduce> {
        :my $*IN_REDUCE := 1;
        :my $op;
        <?before '['\S+']'>
        <!before '[' <[ - + ? ~ ^ ]> <[ \w $ @ ]> >  # disallow accidental prefix before termish thing

        '['
        [
        || <op=.infixish('red')> <?[\]]>
        || $<triangle>=[\\]<op=.infixish('tri')> <?[\]]>
        || <!>
        ]
        ']'
        { $op := $<op>; }

        <.can_meta($op, "reduce with")>

        [
        || <!{ $op<OPER><O><diffy> }>
        || <?{ $op<OPER><O><pasttype> eq 'chain' }>
        || { self.typed_panic: "X::Syntax::CannotMeta", meta => "reduce with", operator => ~$op<OPER><sym>, dba => ~$op<OPER><O><dba>, reason => 'diffy and not chaining' }
        ]

        <args>
    }

    token postfix_prefix_meta_operator:sym<»> {
        [ <sym> | '>>' ]
        [ <!{ $*QSIGIL }> || <![(]> ]
    }

    token prefix_postfix_meta_operator:sym<«> {
        <sym> | '<<'
    }

    token infix_circumfix_meta_operator:sym<« »> {
        $<opening>=[ '«' | '»' ]
        {} <infixish('hyper')>
        $<closing>=[ '«' | '»' || <.missing("« or »")> ]
        <.can_meta($<infixish>, "hyper with")>
        {} <O=.AS_MATCH($<infixish><OPER><O>)>
    }

    token infix_circumfix_meta_operator:sym«<< >>» {
        $<opening>=[ '<<' | '>>' ]
        {} <infixish('HYPER')>
        $<closing>=[ '<<' | '>>' || <.missing("<< or >>")> ]
        {} <O=.AS_MATCH($<infixish><OPER><O>)>
    }

    method AS_MATCH($v) {
        my $cur  := self.'!cursor_start_cur'();
        $cur.'!cursor_pass'(self.pos());
        nqp::bindattr($cur, NQPCursor, '$!match', $v);
        $cur
    }
    method revO($from) {
        my $O   := nqp::clone($from<OPER><O>);
        my $cur := self.'!cursor_start_cur'();
        $cur.'!cursor_pass'(self.pos());
        if    $O<assoc> eq 'right' { $O<assoc> := 'left' }
        elsif $O<assoc> eq 'left'  { $O<assoc> := 'right' }
        nqp::bindattr($cur, NQPCursor, '$!match', $O);
        $cur
    }

    proto token dotty { <...> }
    token dotty:sym<.> {
        <sym> <dottyop>
        <O('%methodcall')>
    }

    token dotty:sym<.*> {
        $<sym>=['.' [ <[+*?=]> | '^' '!'? ]] <dottyop>
        <O('%methodcall')>
    }

    token dottyop {
        :dba('dotty method or postfix')
        <.unsp>?
        [
        | <methodop>
        | <colonpair>
        | <!alpha> <postop> $<O> = {$<postop><O>} $<sym> = {$<postop><sym>}
        ]
    }

    token privop {
        '!' <methodop>
        <O('%methodcall')>
    }

    token methodop {
        [
        | <longname>
        | <?[$@&]> <variable> { self.check_variable($<variable>) }
        | <?['"]>
            [ <!{$*QSIGIL}> || <!before '"' <-["]>*? [\s|$] > ] # dwim on "$foo."
            <quote>
            [ <?before '(' | '.(' | '\\'> || <.panic: "Quoted method name requires parenthesized arguments. If you meant to concatenate two strings, use '~'."> ]
        ] <.unsp>?
        :dba('method arguments')
        [
            [
            | <?[(]> <args>
            | ':' <?before \s | '{'> <!{ $*QSIGIL }> <args=.arglist>
            ]
            || <!{ $*QSIGIL }> <?>
            || <?{ $*QSIGIL }> <?[.]> <?>
        ] <.unsp>?
    }

    token dottyopish {
        <term=.dottyop>
    }

    token postcircumfix:sym<[ ]> {
        :my $*QSIGIL := '';
        :dba('subscript')
        '[' ~ ']' [ <.ws> <semilist> ]
        <O('%methodcall')>
    }

    token postcircumfix:sym<{ }> {
        :my $*QSIGIL := '';
        :dba('subscript')
        '{' ~ '}' [ <.ws> <semilist> ]
        <O('%methodcall')>
    }

    token postcircumfix:sym<ang> {
        '<'
        [
        || <nibble(self.quote_lang(%*LANG<Quote>, "<", ">", ['q', 'w', 'v']))> '>'
        || <?before \h* [ \d | <sigil> | ':' ] >
           { $/.CURSOR.panic("Whitespace required before < operator") }
        || { $/.CURSOR.panic("Unable to parse quote-words subscript; couldn't find right angle quote") }
        ]
        <O('%methodcall')>
    }

    token postcircumfix:sym«<< >>» {
        :dba('shell-quote words')
        '<<'
        [
        || <nibble(self.quote_lang(%*LANG<Quote>, "<<", ">>", ['qq', 'ww', 'v']))> '>>'
        || { $/.CURSOR.panic("Unable to parse quote-words subscript; couldn't find right double-angle quote") }
        ]
        <O('%methodcall')>
    }

    token postcircumfix:sym<« »> {
        :dba('shell-quote words')
        '«'
        [
        || <nibble(self.quote_lang(%*LANG<Quote>, "«", "»", ['qq', 'ww', 'v']))> '»'
        || { $/.CURSOR.panic("Unable to parse quote-words subscript; couldn't find right double-angle quote") }
        ]
        <O('%methodcall')>
    }

    token postcircumfix:sym<( )> {
        :dba('argument list')
        '(' ~ ')' [ <.ws> <arglist> ]
        <O('%methodcall')>
    }

    # These are here to prevent us generating the candidates when parsing CORE.setting.
    token postcircumfix:sym<[; ]> { <!> }
    token postcircumfix:sym<{; }> { <!> }

    token postfix:sym<i>  { <sym> >> <O('%methodcall')> }

    token prefix:sym<++>  { <sym>  <O('%autoincrement')> }
    token prefix:sym<-->  { <sym>  <O('%autoincrement')> }
    token postfix:sym<++> { <sym>  <O('%autoincrement')> }
    token postfix:sym<--> { <sym>  <O('%autoincrement')> }
    token postfix:sym<ⁿ> { <sign=[⁻⁺¯]>? <dig=[⁰¹²³⁴⁵⁶⁷⁸⁹]>+ <O('%autoincrement')> }

    # TODO: report the correct bracket in error message
    token postfix:sym«->» {
        <sym>
        [
        |  ['[' | '{' | '(' ] <.obs('->(), ->{} or ->[] as postfix dereferencer', '.(), .[] or .{} to deref, or whitespace to delimit a pointy block')>
        | <.obs('-> as postfix', 'either . to call a method, or whitespace to delimit a pointy block')>
        ]
    }

    token infix:sym<**>   { <sym>  <O('%exponentiation')> }

    token prefix:sym<+>   { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<~~>  { <sym> <.dupprefix('~~')> <O('%symbolic_unary')> }
    token prefix:sym<~>   { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<->   { <sym> <O('%symbolic_unary')> }
    token prefix:sym<−>   { <sym> <O('%symbolic_unary')> }
    token prefix:sym<??>  { <sym> <.dupprefix('??')> <O('%symbolic_unary')> }
    token prefix:sym<?>   { <sym> <!before '??'> <O('%symbolic_unary')> }
    token prefix:sym<!>   { <sym> <!before '!!'> <O('%symbolic_unary')> }
    token prefix:sym<|>   { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<+^>  { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<~^>  { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<?^>  { <sym>  <O('%symbolic_unary')> }
    token prefix:sym<^^>  { <sym> <.dupprefix('^^')> <O('%symbolic_unary')> }
    token prefix:sym<^>   {
        <sym>  <O('%symbolic_unary')>
        <?before \d+ <?before \. <?alpha> > <.worry: "Precedence of ^ is looser than method call; please parenthesize"> >?
    }

    token infix:sym<*>    { <sym>  <O('%multiplicative')> }
    token infix:sym<×>    { <sym>  <O('%multiplicative')> }
    token infix:sym</>    { <sym>  <O('%multiplicative')> }
    token infix:sym<÷>    { <sym>  <O('%multiplicative')> }
    token infix:sym<div>  { <sym> >> <O('%multiplicative')> }
    token infix:sym<gcd>  { <sym> >> <O('%multiplicative')> }
    token infix:sym<lcm>  { <sym> >> <O('%multiplicative')> }
    token infix:sym<%>    { <sym>  <O('%multiplicative')> }
    token infix:sym<mod>  { <sym> >> <O('%multiplicative')> }
    token infix:sym<%%>   { <sym>  <O('%multiplicative, :iffy<1>')> }
    token infix:sym<+&>   { <sym>  <O('%multiplicative')> }
    token infix:sym<~&>   { <sym>  <O('%multiplicative')> }
    token infix:sym<?&>   { <sym>  <O('%multiplicative, :iffy<1>')> }
    token infix:sym«+<»   { <sym> [ <!{ $*IN_META }> || <?before '<<'> || <![<]> ] <O('%multiplicative')> }
    token infix:sym«+>»   { <sym> [ <!{ $*IN_META }> || <?before '>>'> || <![>]> ] <O('%multiplicative')> }
    token infix:sym«~<»   { <sym> [ <!{ $*IN_META }> || <?before '<<'> || <![<]> ] <O('%multiplicative')> }
    token infix:sym«~>»   { <sym> [ <!{ $*IN_META }> || <?before '>>'> || <![>]> ] <O('%multiplicative')> }

    token infix:sym«<<» { <sym> <!{ $*IN_META }> <?[\s]> <.sorryobs('<< to do left shift', '+< or ~<')> <O('%multiplicative')> }

    token infix:sym«>>» { <sym> <!{ $*IN_META }> <?[\s]> <.sorryobs('>> to do right shift', '+> or ~>')> <O('%multiplicative')> }

    token infix:sym<+>    { <sym>  <O('%additive')> }
    token infix:sym<->    {
       # We want to match in '$a >>->> $b' but not 'if $a -> { ... }'.
        <sym> [<?before '>>'> || <![>]>]
        <O('%additive')>
    }
    token infix:sym<−>    { <sym>  <O('%additive')> }
    token infix:sym<+|>   { <sym>  <O('%additive')> }
    token infix:sym<+^>   { <sym>  <O('%additive')> }
    token infix:sym<~|>   { <sym>  <O('%additive')> }
    token infix:sym<~^>   { <sym>  <O('%additive')> }
    token infix:sym<?|>   { <sym>  <O('%additive, :iffy<1>')> }
    token infix:sym<?^>   { <sym>  <O('%additive, :iffy<1>')> }

    token infix:sym<x>    { <sym> >> <O('%replication')> }
    token infix:sym<xx>    { <sym> >> <O('%replication_xx')> }

    token infix:sym<~>    { <sym>  <O('%concatenation')> }
    token infix:sym<.>    { <sym> <ws>
        <!{ $*IN_REDUCE }>
        [<!alpha>
            {
                my $pre := nqp::substr(self.orig, self.from - 1, 1);
                $<ws> ne ''
                ?? $¢.obs('. to concatenate strings', '~')
                !! $pre ~~ /^\s$/
                    ?? $¢.malformed('postfix call (only alphabetic methods may be detached)')
                    !! $¢.malformed('postfix call')
            }
        ]?
        <O('%dottyinfix')>
    }
    token infix:sym<∘>   { <sym>  <O('%concatenation')> }
    token infix:sym<o>   { <sym>  <O('%concatenation')> }

    token infix:sym<&>   { <sym> <O('%junctive_and, :iffy<1>')> }
    token infix:sym<(&)> { <sym> <O('%junctive_and')> }
    token infix:sym«∩»   { <sym> <O('%junctive_and')> }
    token infix:sym<(.)> { <sym> <O('%junctive_and')> }
    token infix:sym«⊍»   { <sym> <O('%junctive_and')> }

    token infix:sym<|>    { <sym> <O('%junctive_or, :iffy<1>')> }
    token infix:sym<^>    { <sym> <O('%junctive_or, :iffy<1>')> }
    token infix:sym<(|)>  { <sym> <O('%junctive_or')> }
    token infix:sym«∪»    { <sym> <O('%junctive_or')> }
    token infix:sym<(^)>  { <sym> <O('%junctive_or')> }
    token infix:sym«⊖»    { <sym> <O('%junctive_or')> }
    token infix:sym<(+)>  { <sym> <O('%junctive_or')> }
    token infix:sym«⊎»    { <sym> <O('%junctive_or')> }
    token infix:sym<(-)>  { <sym> <O('%junctive_or')> }
    token infix:sym«∖»    { <sym> <O('%junctive_or')> }

    token prefix:sym<let>  { <sym><.kok> <O('%named_unary')> { $*W.give_cur_block_let($/) } }
    token prefix:sym<temp> { <sym><.kok> <O('%named_unary')> { $*W.give_cur_block_temp($/) } }

    token infix:sym«=~=»  { <sym>  <O('%chaining')> }
    token infix:sym«≅»    { <sym>  <O('%chaining')> }
    token infix:sym«==»   { <sym>  <O('%chaining')> }
    token infix:sym«!=»   { <sym> <?before \s|']'> <O('%chaining')> }
    token infix:sym«<=»   { <sym>  <O('%chaining')> }
    token infix:sym«>=»   { <sym>  <O('%chaining')> }
    token infix:sym«<»    { <sym>  <O('%chaining')> }
    token infix:sym«>»    { <sym>  <O('%chaining')> }
    token infix:sym«eq»   { <sym> >> <O('%chaining')> }
    token infix:sym«ne»   { <sym> >> <O('%chaining')> }
    token infix:sym«le»   { <sym> >> <O('%chaining')> }
    token infix:sym«ge»   { <sym> >> <O('%chaining')> }
    token infix:sym«lt»   { <sym> >> <O('%chaining')> }
    token infix:sym«gt»   { <sym> >> <O('%chaining')> }
    token infix:sym«=:=»  { <sym>  <O('%chaining')> }
    token infix:sym<===>  { <sym>  <O('%chaining')> }
    token infix:sym<eqv>    { <sym> >> <O('%chaining')> }
    token infix:sym<before> { <sym> >> <O('%chaining')> }
    token infix:sym<after>  { <sym> >> <O('%chaining')> }
    token infix:sym<~~>   { <sym> <O('%chaining')> }
    token infix:sym<!~~>  { <sym> <O('%chaining')> }
    token infix:sym<(elem)> { <sym> <O('%chaining')> }
    token infix:sym«∈»      { <sym> <O('%chaining')> }
    token infix:sym«∉»      { <sym> <O('%chaining')> }
    token infix:sym<(cont)> { <sym> <O('%chaining')> }
    token infix:sym«∋»      { <sym> <O('%chaining')> }
    token infix:sym«∌»      { <sym> <O('%chaining')> }
    token infix:sym«(<)»    { <sym> <O('%chaining')> }
    token infix:sym«⊂»      { <sym> <O('%chaining')> }
    token infix:sym«⊄»      { <sym> <O('%chaining')> }
    token infix:sym«(>)»    { <sym> <O('%chaining')> }
    token infix:sym«⊃»      { <sym> <O('%chaining')> }
    token infix:sym«⊅»      { <sym> <O('%chaining')> }
    token infix:sym«(<=)»   { <sym> <O('%chaining')> }
    token infix:sym«⊆»      { <sym> <O('%chaining')> }
    token infix:sym«⊈»      { <sym> <O('%chaining')> }
    token infix:sym«(>=)»   { <sym> <O('%chaining')> }
    token infix:sym«⊇»      { <sym> <O('%chaining')> }
    token infix:sym«⊉»      { <sym> <O('%chaining')> }
    token infix:sym«(<+)»   { <sym> <O('%chaining')> }
    token infix:sym«≼»      { <sym> <O('%chaining')> }
    token infix:sym«(>+)»   { <sym> <O('%chaining')> }
    token infix:sym«≽»      { <sym> <O('%chaining')> }

    token infix:sym<&&>   { <sym>  <O('%tight_and, :iffy<1>, :pasttype<if>')> }

    token infix:sym<||>   { <sym>  <O('%tight_or, :iffy<1>, :assoc<left>, :pasttype<unless>')> }
    token infix:sym<^^>   { <sym>  <O('%tight_or, :iffy<1>, :pasttype<xor>, :thunky<..t>')> }
    token infix:sym<//>   { <sym>  <O('%tight_or, :assoc<left>, :pasttype<defor>')> }
    token infix:sym<min>  { <sym> >> <O('%tight_or_minmax')> }
    token infix:sym<max>  { <sym> >> <O('%tight_or_minmax')> }

    token infix:sym<?? !!> {
        :my $*GOAL := '!!';
        '??'
        <.ws>
        <EXPR('i=')>
        [ '!!'
        || <?before '::' <-[=]>> { self.typed_panic: "X::Syntax::ConditionalOperator::SecondPartInvalid", second-part => "::" }
        || <?before ':' <-[=\w]>> { self.typed_panic: "X::Syntax::ConditionalOperator::SecondPartInvalid", second-part => ":" }
        || <infixish> { self.typed_panic: "X::Syntax::ConditionalOperator::PrecedenceTooLoose", operator => ~$<infixish> }
        || <?{ ~$<EXPR> ~~ / '!!' / }> { self.typed_panic: "X::Syntax::ConditionalOperator::SecondPartGobbled" }
        || <?before \N*? [\n\N*?]? '!!'> { self.typed_panic: "X::Syntax::Confused", reason => "Confused: Bogus code found before the !! of conditional operator" }
        || { self.typed_panic: "X::Syntax::Confused", reason => "Confused: Found ?? but no !!" }
        ]
        <O('%conditional, :reducecheck<ternary>, :pasttype<if>')>
    }

    token infix_prefix_meta_operator:sym<!> {
        <sym> <![!]> {} [ <infixish('neg')> || <.panic: "Negation metaoperator not followed by valid infix"> ]
        [
        || <?{ $<infixish>.Str eq '=' }> <O('%chaining')>
        || <.can_meta($<infixish>, "negate")> <?{ $<infixish><OPER><O><iffy> }> <O=.AS_MATCH($<infixish><OPER><O>)>
        || { self.typed_panic: "X::Syntax::CannotMeta", meta => "negate", operator => ~$<infixish>, dba => ~$<infixish><OPER><O><dba>, reason => "not iffy enough" }
        ]
    }

    token infix_prefix_meta_operator:sym<R> {
        <sym> <infixish('R')> {}
        <.can_meta($<infixish>, "reverse the args of")>
        <O=.revO($<infixish>)>
    }

    token infix_prefix_meta_operator:sym<S> {
        <sym> <infixish('S')> {}
        <.can_meta($<infixish>, "sequence the args of")>
        <O=.AS_MATCH($<infixish><OPER><O>)>
    }

    token infix_prefix_meta_operator:sym<X> {
        <sym> <infixish('X')> {}
        <.can_meta($<infixish>, "cross with")>
        <O('%list_infix')>

    }

    token infix_prefix_meta_operator:sym<Z> {
        <sym> <infixish('Z')> {}
        <.can_meta($<infixish>, "zip with")>
        <O('%list_infix')>
    }

    token infix:sym<minmax> { <sym> >> <O('%list_infix')> }

    token infix:sym<:=> {
        <sym>  <O('%list_assignment')>
    }

    token infix:sym<::=> {
        <sym>  <O('%item_assignment')> <.NYI('"::="')>
    }

    token infix:sym<.=> { <sym> <O('%dottyinfix')> }

    # Should probably have <!after '='> to agree w/spec, but after NYI.
    # Modified infix != below instead to prevent misparse
    # token infix_postfix_meta_operator:sym<=>($op) {
    # use $*OPER until NQP/Rakudo supports proto tokens with arguments
    token infix_postfix_meta_operator:sym<=> {
        :my $prec;
        :my %fudge_oper;
        '='
        { %fudge_oper<OPER> := $*OPER }
        <.can_meta(%fudge_oper, "make assignment out of")>
        [ <!{ $*OPER<O><diffy> }> || <.can_meta(%fudge_oper, "make assignment out of", "diffy")> ]
        {
            $<sym> := $*OPER<sym> ~ '=';
            if $*OPER<O><prec> gt 'g=' {
                $prec := '%item_assignment';
            }
            else {
                $prec := '%list_assignment';
            }
        }
        <O("$prec, :dba<assignment operator>, :iffy<0>")> {}
    }

    token infix:sym«=>» { <sym> <O('%item_assignment')> }

    token prefix:sym<so> { <sym><.end_prefix> <O('%loose_unary')> }
    token prefix:sym<not>  { <sym><.end_prefix> <O('%loose_unary')> }

    token infix:sym<,>    {
        <.unsp>? <sym> <O('%comma, :fiddly<0>')>
        # TODO: should be <.worry>, not <.panic>
        [ <?before \h*['...'|'…']> <.panic: "Comma found before apparent series operator; please remove comma (or put parens\n    around the ... listop, or use 'fail' instead of ...)"> ]?
        { $*INVOCANT_OK := 0 }
    }
    token infix:sym<:>    {
        <?{ $*INVOCANT_OK && $*GOAL ne '!!' }>
        <.unsp>? <sym> <?before \s | <.terminator> | $ >
        <O('%comma, :fiddly<0>')>
        [ <?{ $*INVOCANT_OK }> || <.panic: "Invocant colon not allowed here"> ]
        { $*INVOCANT_OK := 0; }
    }

    token infix:sym<Z>    { <!before <sym> <infixish> > <sym>  <O('%list_infix')> }
    token infix:sym<X>    { <!before <sym> <infixish> > <sym>  <O('%list_infix')> }

    token infix:sym<...>  { <sym> <O('%list_infix')> }
    token infix:sym<…>    { <sym> <O('%list_infix')> }
    token infix:sym<...^> { <sym>  <O('%list_infix')> }
    token infix:sym<…^>   { <sym>  <O('%list_infix')> }
    # token term:sym<...>   { <sym> <args>**0..1 <O(|%list_prefix)> }

    token infix:sym<?>    { <sym> {} <![?]> <?before <-[;]>*?':'> <.obs('? and : for the ternary conditional operator', '?? and !!')> <O('%conditional')> }

    token infix:sym<ff> { <sym> <O('%conditional_ff')> }
    token infix:sym<^ff> { <sym> <O('%conditional_ff')> }
    token infix:sym<ff^> { <sym> <O('%conditional_ff')> }
    token infix:sym<^ff^> { <sym> <O('%conditional_ff')> }

    token infix:sym<fff> { <sym> <O('%conditional_ff')> }
    token infix:sym<^fff> { <sym> <O('%conditional_ff')> }
    token infix:sym<fff^> { <sym> <O('%conditional_ff')> }
    token infix:sym<^fff^> { <sym> <O('%conditional_ff')> }

    token infix:sym<=> {
        <sym>
        [
        || <?{ $*LEFTSIGIL eq '$' || $*IN_META }> <O('%item_assignment')>
        || <O('%list_assignment')>
        ]
        { $*LEFTSIGIL := '' }
    }

    token infix:sym<and>  { <sym> >> <O('%loose_and, :iffy<1>, :pasttype<if>')> }
    token infix:sym<andthen> { <sym> >> <O('%loose_andthen, :assoc<list>')> }
    token infix:sym<notandthen> { <sym> >> <O('%loose_andthen, :assoc<list>')> }

    token infix:sym<or>   { <sym> >> <O('%loose_or, :iffy<1>, :assoc<left>, :pasttype<unless>')> }
    token infix:sym<xor>  { <sym> >> <O('%loose_or, :iffy<1>, :pasttype<xor>')> }
    token infix:sym<orelse> { <sym> >> <O('%loose_orelse, :assoc<list>, :pasttype<defor>')> }

    token infix:sym«<==»  { <sym> <O('%sequencer')> }
    token infix:sym«==>»  { <sym> <O('%sequencer')> }
    token infix:sym«<<==» { <sym> <O('%sequencer')> }
    token infix:sym«==>>» { <sym> <O('%sequencer')> }

    token infix:sym<..>   { <sym> [<!{ $*IN_META }> <?[)\]]> <.panic: "Please use ..* for indefinite range">]? <O('%structural')> }
    token infix:sym<^..>  { <sym> <O('%structural')> }
    token infix:sym<..^>  { <sym> <O('%structural')> }
    token infix:sym<^..^> { <sym> <O('%structural')> }

    token infix:sym<leg>  { <sym> >> <O('%structural')> }
    token infix:sym<cmp>  { <sym> >> <O('%structural')> }
    token infix:sym«<=>»  { <sym> <O('%structural')> }

    token infix:sym<but>  { <sym> >> <O('%structural')> }
    token infix:sym<does> { <sym> >> <O('%structural')> }

    token infix:sym<!~> { <sym> \s <.obs('!~ to do negated pattern matching', '!~~')> <O('%chaining')> }
    token infix:sym<=~> { <sym> <.obs('=~ to do pattern matching', '~~')> <O('%chaining')> }

    method add_mystery($token, $pos, $ctx) {
        my $name := ~$token;
        $name := nqp::substr($name,1) if nqp::eqat($name,"&",0);
        my $categorical := $name ~~ /^((\w+?fix) [ ':<'\s*(\S+?)\s*'>' | ':«'\s*(\S+?)\s*'»' ])$/;
        if $categorical {    # Does it look like a metaop?
            my $cat := ~$categorical[0][0];
            my $op := ~$categorical[0][1];
            return self if $op eq '!=';
            my $lang := self.'!cursor_init'($op, :p(0));
            my $meth := $cat eq 'infix' || $cat eq 'prefix' || $cat eq 'postfix' ?? $cat ~ 'ish' !! $cat;
            $meth := 'term:sym<reduce>' if $cat eq 'prefix' && $op ~~ /^ \[ .* \] $ /;
            # nqp::printfh(nqp::getstderr(), "$meth $op\n");
            my $cursor := $lang."$meth"();
            my $match := $cursor.MATCH;
            if $cursor.pos == nqp::chars($op) && (
                $match<infix_prefix_meta_operator> ||
                $match<infix_circumfix_meta_operator> ||
                $match<infix_postfix_meta_operator> ||
                $match<prefix_postfix_meta_operator> ||
                $match<postfix_prefix_meta_operator> ||
                $match<op>)
            {
                my $META := $match.ast;
                $META := $META[0] unless $META.name;
                $META.name('&METAOP_HYPER_POSTFIX') if $META.name eq '&METAOP_HYPER_POSTFIX_ARGS';
                # nqp::printfh(nqp::getstderr(), $META.dump);
                my $fun := $*W.compile_time_evaluate(self.MATCH,$META);
                $*W.install_lexical_symbol($*W.cur_lexpad(),'&' ~ $categorical[0],$fun);
                $fun.set_name($name);
                return self;
            }
        }
        unless $name eq '' || $*W.is_lexical('&' ~ $name) {
            my $lex := $*W.cur_lexpad();
            my $key := $name ~ '-' ~ $lex.cuid;
            if nqp::existskey(%*MYSTERY, $key) {
                nqp::push(%*MYSTERY{$key}<pos>, $pos);
            }
            else {
                %*MYSTERY{$key} := nqp::hash(
                    'lex', $lex,
                    'name', $name,
                    'ctx', $ctx,
                    'pos', [$pos]);
            }
        }
        self;
    }

    method explain_mystery() {
        my %post_types;
        my %unk_types;
        my %unk_routines;

        sub push_lines(@target, @pos) {
            for @pos {
                nqp::push(@target, HLL::Compiler.lineof(self.orig, $_, :cache(1)));
            }
        }

        my %routine_suggestion := hash();
        my %type_suggestion := hash();

        for %*MYSTERY {
            my %sym  := $_.value;
            my $name := %sym<name>;
            my $decl := $*W.is_lexically_visible($name, %sym<lex>);
            if $decl == 2 {
                # types may not be post-declared
                %post_types{$name} := [] unless %post_types{$name};
                push_lines(%post_types{$name}, %sym<pos>);
                next;
            }

            next if $decl == 1;
            next if $*W.is_lexically_visible('&' ~ $name, %sym<lex>);

            # no sigil or &
            if nqp::eqat($name, '&', 0) || $name ge 'a' {
                %unk_routines{$name} := [] unless %unk_routines{$name};
                my @suggs := $*W.suggest_routines($name);
                %routine_suggestion{$name} := @suggs;
                push_lines(%unk_routines{$name}, %sym<pos>);
            }

            # hopefully improve error reporting
            else {
                %unk_types{$name} := [] unless %unk_types{$name};
                my @suggs := $*W.suggest_typename($name);
                %type_suggestion{$name} := @suggs;
                push_lines(%unk_types{$name}, %sym<pos>);
            }
        }

        if %post_types || %unk_types || %unk_routines {
            self.typed_sorry('X::Undeclared::Symbols',
                :%post_types, :%unk_types, :%unk_routines,
                :%routine_suggestion, :%type_suggestion);
        }

        self;
    }

    method cry_sorrows() {
        if @*SORROWS {
            if +@*SORROWS == 1 && !@*WORRIES {
                @*SORROWS[0].throw()
            }
            else {
                $*W.group_exception(@*SORROWS.pop).throw();
            }
        }
        self
    }

    method add_variable($name) {
        my $categorical := $name ~~ /^'&'((\w+) [ ':<'\s*(\S+?)\s*'>' | ':«'\s*(\S+?)\s*'»' ])$/;
        my $cat := ~$categorical[0][0];
        if $categorical && nqp::can(self,$cat) {
            self.add_categorical($cat, ~$categorical[0][1],
                $cat ~ $*W.canonicalize_pair('sym', $categorical[0][1]),
                ~$categorical[0]);
        }
    }

    # Called when we add a new choice to an existing syntactic category, for
    # example new infix operators add to the infix category. Augments the
    # grammar as needed.
    my %categorically-won't-work := nqp::hash(
        'infix:sym<=>', NQPMu,
        'infix:sym<:=>', NQPMu,
        'infix:sym<::=>', NQPMu,
        'infix:sym<~~>', '(consider implementing an ACCEPTS method)',
        'prefix:sym<|>', NQPMu);
    method add_categorical($category, $opname, $canname, $subname, $declarand?, :$defterm) {
        my $self := self;

        # Ensure it's not a null name or a compiler-handled op.
        if $opname eq '' {
            self.typed_panic('X::Syntax::Extension::Null');
        }
        if nqp::existskey(%categorically-won't-work, $canname) && !$*COMPILING_CORE_SETTING {
            if %categorically-won't-work{$canname} -> $hint {
                self.typed_panic('X::Syntax::Extension::SpecialForm', :$category, :$opname, :$hint);
            }
            else {
                self.typed_panic('X::Syntax::Extension::SpecialForm', :$category, :$opname);
            }
        }

        # If we already have the required operator in the grammar, just return.
        if nqp::can(self, $canname) {
            return 1;
        }

        # Work out what default precedence we want, or if it's more special than
        # just an operator.
        my $prec;
        my $is_oper;
        my $is_term := 0;
        if $category eq 'infix' {
            $prec := '%additive';
            $is_oper := 1;
        }
        elsif $category eq 'prefix' {
            $prec := '%symbolic_unary';
            $is_oper := 1;
        }
        elsif $category eq 'postfix' {
            $prec := '%autoincrement';
            $is_oper := 1;
        }
        elsif $category eq 'postcircumfix'
           || $category eq 'circumfix' {
            $is_oper := 0;
        }
        elsif $category eq 'trait_mod' {
            return 0;
        }
        elsif $category eq 'term' {
            $is_term := 1;
        }
        elsif $category eq 'METAOP_TEST_ASSIGN' {
            return 0;
        }
        else {
            self.typed_panic('X::Syntax::Extension::Category', :$category);
        }

        # when importing, reuse known precedence overrides
        if $prec && nqp::can($declarand,'prec') {
            $prec := $prec ~ ', ' ~ $declarand.prec.pairs.map(sub ($p) { ':' ~ $p.key ~ '<' ~ $p.value ~ '>' }).join(', ');
        }

        my @parts := nqp::split(' ', $opname);

# The settings should only have 1 grammar, otherwise it will slow down
# loading of rakudo significantly on *every* run.  This is a canary that
# will let itself be known should someone make changes to the setting that
# would cause a grammar change, and thus a slowdown.
if $*COMPILING_CORE_SETTING {
    self.panic("don't change grammar in the setting, please!");
}

        if $is_term {
            my role Term[$meth_name, $op] {
                token ::($meth_name) { $<sym>=[$op] }
            }
            if +@parts > 1 {
                self.typed_panic('X::Syntax::AddCategorical::TooManyParts', :$category, :needs(1));
            }
            self.HOW.mixin(self, Term.HOW.curry(Term, $canname, $opname));
        }
        # Mix an appropraite role into the grammar for parsing the new op.
        elsif $is_oper {
            my role Oper[$meth_name, $op, $precedence, $declarand] {
                token ::($meth_name) { $<sym>=[$op] <O=.genO($precedence, $declarand)> }
            }
            if +@parts > 1 {
                self.typed_panic('X::Syntax::AddCategorical::TooManyParts', :$category, :needs(1));
            }
            self.HOW.mixin(self, Oper.HOW.curry(Oper, $canname, $opname, $prec, $declarand));
        }
        elsif $category eq 'postcircumfix' {
            # Find opener and closer and parse an EXPR between them.
            # XXX One day semilist would be nice, but right now that
            # runs us into fun with terminators.
            if +@parts < 2 {
                self.typed_panic('X::Syntax::AddCategorical::TooFewParts', :$category, :needs(2));
            }
            elsif +@parts > 2 {
                self.typed_panic('X::Syntax::AddCategorical::TooManyParts', :$category, :needs(2));
            }
            my role Postcircumfix[$meth_name, $starter, $stopper] {
                token ::($meth_name) {
                    :my $*GOAL := $stopper;
                    :my $stub := %*LANG<MAIN> := nqp::getlex('$¢').unbalanced($stopper);
                    $starter ~ $stopper [ <.ws> <statement> ]
                    <O('%methodcall')>
                }
            }
            self.HOW.mixin(self, Postcircumfix.HOW.curry(Postcircumfix, $canname, @parts[0], @parts[1]));
        }
        else {
            # Find opener and closer and parse an EXPR between them.
            if +@parts < 2 {
                self.typed_panic('X::Syntax::AddCategorical::TooFewParts', :$category, :needs(2));
            }
            elsif +@parts > 2 {
                self.typed_panic('X::Syntax::AddCategorical::TooManyParts', :$category, :needs(2));
            }
            my role Circumfix[$meth_name, $starter, $stopper] {
                token ::($meth_name) {
                    :my $*GOAL := $stopper;
                    :my $stub := %*LANG<MAIN> := nqp::getlex('$¢').unbalanced($stopper);
                    $starter ~ $stopper <semilist>
                }
            }
            self.HOW.mixin(self, Circumfix.HOW.curry(Circumfix, $canname, @parts[0], @parts[1]));
        }

        # This also becomes the current MAIN. Also place it in %?LANG.
        %*LANG<MAIN> := self.WHAT;

        # Declarand should get precedence traits.
        if $is_oper && nqp::isconcrete($declarand) {
            my $base_prec := self.O($prec).MATCH<prec>;
            $*W.apply_trait(self.MATCH, '&trait_mod:<is>', $declarand,
                :prec(nqp::hash('prec', $base_prec)));
        }

        # May also need to add to the actions.
        if $category eq 'postcircumfix' {
            my role PostcircumfixAction[$meth, $subname] {
                method ::($meth)($/) {
                    make QAST::Op.new(
                        :op('call'), :name('&' ~ $subname), :node($/),
                        $<statement>.ast
                    );
                }
            };
            %*LANG<MAIN-actions> := $*ACTIONS.HOW.mixin($*ACTIONS,
                PostcircumfixAction.HOW.curry(PostcircumfixAction, $canname, $subname));
        }
        elsif $category eq 'circumfix' {
            my role CircumfixAction[$meth, $subname] {
                method ::($meth)($/) {
                    make QAST::Op.new(
                        :op('call'), :name('&' ~ $subname), :node($/),
                        $<semilist>.ast
                    );
                }
            };
            %*LANG<MAIN-actions> := $*ACTIONS.HOW.mixin($*ACTIONS,
                CircumfixAction.HOW.curry(CircumfixAction, $canname, $subname));
        }
        elsif $is_term {
            my role TermAction[$meth, $subname] {
                method ::($meth)($/) {
                    make QAST::Op.new(
                        :op('call'), :name('&' ~ $subname), :node($/),
                    );
                }
            };
            my role TermActionConstant[$meth, $name] {
                method ::($meth)($/) {
                    make QAST::Var.new( :$name, :scope('lexical') );
                }
            };
            %*LANG<MAIN-actions> := $*ACTIONS.HOW.mixin($*ACTIONS,
                $defterm
                    ?? TermAction.HOW.curry(TermActionConstant, $canname, $subname)
                    !! TermAction.HOW.curry(TermAction, $canname, $subname));
        }

        $*W.install_lexical_symbol($*W.cur_lexpad(), '%?LANG', $*W.p6ize_recursive(%*LANG));
        return 1;
    }

    method genO($default, $declarand) {
        my $desc := $default;
        if nqp::can($declarand, 'prec') {
            my %extras := $declarand.prec.FLATTENABLE_HASH;
            for %extras {
                $desc := "$desc, :" ~ $_.key ~ "<" ~ $_.value ~ ">";
            }
        }
        self.O($desc)
    }
}

grammar Perl6::QGrammar is HLL::Grammar does STD {

    method throw_unrecog_backslash_seq ($sequence) {
        self.typed_sorry('X::Backslash::UnrecognizedSequence', :$sequence);
    }

    proto token escape {*}
    proto token backslash {*}

    role b1 {
        token escape:sym<\\> { <sym> {} <item=.backslash> }
        token backslash:sym<qq> { <?[q]> <quote=.LANG('MAIN','quote')> }
        token backslash:sym<\\> { <text=.sym> }
        token backslash:delim { <text=.starter> | <text=.stopper> }
        token backslash:sym<a> { <sym> }
        token backslash:sym<b> { <sym> }
        token backslash:sym<c> { <sym> <charspec> }
        token backslash:sym<e> { <sym> }
        token backslash:sym<f> { <sym> }
        token backslash:sym<N> { <?before 'N{'<[A..Z]>> <.obs('\N{CHARNAME}','\c[CHARNAME]')>  }
        token backslash:sym<n> { <sym> }
        token backslash:sym<o> { :dba('octal character') <sym> [ <octint> | '[' ~ ']' <octints> | '{' <.obsbrace> ] }
        token backslash:sym<r> { <sym> }
        token backslash:sym<rn> { 'r\n' }
        token backslash:sym<t> { <sym> }
        token backslash:sym<x> { :dba('hex character') <sym> [ <hexint> | '[' ~ ']' <hexints> | '{' <.obsbrace> ] }
        token backslash:sym<0> { <sym> }
        token backslash:sym<1> { <[1..9]>\d* {} <.sorry("Unrecognized backslash sequence (did you mean \${$/ - 1}?)")> }
    }

    role b0 {
        token escape:sym<\\> { <!> }
    }

    role c1 {
        token escape:sym<{ }> { :my $*ESCAPEBLOCK := 1; <?[{]> <!RESTRICTED> <block=.LANG('MAIN','block')> }
    }

    role c0 {
        token escape:sym<{ }> { <!> }
    }

    role s1 {
        token escape:sym<$> {
            :my $*QSIGIL := '$';
            <?[$]>
            <!RESTRICTED>
            [ <EXPR=.LANG('MAIN', 'EXPR', 'y=')> || { $*W.throw($/, 'X::Backslash::NonVariableDollar') } ]
        }
    }

    role s0 {
        token escape:sym<$> { <!> }
    }

    role a1 {
        token escape:sym<@> {
            :my $*QSIGIL := '@';
            <?[@]>
            <!RESTRICTED>
            <EXPR=.LANG('MAIN', 'EXPR', 'y=')>
        }
    }

    role a0 {
        token escape:sym<@> { <!> }
    }

    role h1 {
        token escape:sym<%> {
            :my $*QSIGIL := '%';
            <?[%]>
            <!RESTRICTED>
            <EXPR=.LANG('MAIN', 'EXPR', 'y=')>
        }
    }

    role h0 {
        token escape:sym<%> { <!> }
    }

    role f1 {
        token escape:sym<&> {
            :my $*QSIGIL := '&';
            <?[&]>
            <!RESTRICTED>
            <EXPR=.LANG('MAIN', 'EXPR', 'y=')>
        }
    }

    role f0 {
        token escape:sym<&> { <!> }
    }

    role ww {
        token escape:sym<' '> {
            <?[']> <quote=.LANG('MAIN','quote')>
        }
        token escape:sym<‘ ’> {
            <?[‘]> <quote=.LANG('MAIN','quote')>
        }
        token escape:sym<" "> {
            <?["]> <quote=.LANG('MAIN','quote')>
        }
        token escape:sym<“ ”> {
            <?[“]> <quote=.LANG('MAIN','quote')>
        }
        token escape:sym<colonpair> {
            <?[:]> <!RESTRICTED> <colonpair=.LANG('MAIN','colonpair')>
        }
        token escape:sym<#> {
            <?[#]> <.LANG('MAIN', 'comment')>
        }
    }

    role to[$herelang] {
        method herelang() { $herelang }
        method postprocessors () { nqp::list_s('heredoc') } # heredoc strings are the only postproc when present
    }

    role q {
        token starter { \' }
        token stopper { \' }

        token escape:sym<\\> { <sym> <item=.backslash> }

        token backslash:sym<qq> { <?[q]> <quote=.LANG('MAIN','quote')> }
        token backslash:sym<\\> { <text=.sym> }
        token backslash:delim { <text=.starter> | <text=.stopper> }

        token backslash:sym<miscq> { {} . }

        method tweak_q($v) { self.panic("Too late for :q") }
        method tweak_qq($v) { self.panic("Too late for :qq") }
    }

    role qq does b1 does c1 does s1 does a1 does h1 does f1 {
        token starter { \" }
        token stopper { \" }
        token backslash:sym<unrec> { {} (\w) { self.throw_unrecog_backslash_seq: $/[0].Str } }
        token backslash:sym<misc> { \W }

        method tweak_q($v) { self.panic("Too late for :q") }
        method tweak_qq($v) { self.panic("Too late for :qq") }
    }

    token nibbler {
        :my @*nibbles;
        <.do_nibbling>
    }

    token do_nibbling {
        :my $from := self.pos;
        :my $to   := $from;
        [
            <!stopper>
            [
            || <starter> <nibbler> <stopper>
                {
                    my $c := $/.CURSOR;
                    $to   := $<starter>[-1].from;
                    if $from != $to {
                        nqp::push(@*nibbles, nqp::substr($c.orig, $from, $to - $from));
                    }

                    nqp::push(@*nibbles, $<starter>[-1].Str);
                    nqp::push(@*nibbles, $<nibbler>[-1]);
                    nqp::push(@*nibbles, $<stopper>[-1].Str);

                    $from := $to := $c.pos;
                }
            || <escape>
                {
                    my $c := $/.CURSOR;
                    $to   := $<escape>[-1].from;
                    if $from != $to {
                        nqp::push(@*nibbles, nqp::substr($c.orig, $from, $to - $from));
                    }

                    nqp::push(@*nibbles, $<escape>[-1]);

                    $from := $to := $c.pos;
                }
            || .
            ]
        ]*
        {
            my $c := $/.CURSOR;
            $to   := $c.pos;
            $*LASTQUOTE := [self.pos, $to];
            if $from != $to || !@*nibbles {
                nqp::push(@*nibbles, nqp::substr($c.orig, $from, $to - $from));
            }
        }
    }

    role cc {
        token starter { \' }
        token stopper { \' }

        method ccstate ($s) {
            if $*CCSTATE eq '..' {
                $*CCSTATE := '';
            }
            else {
                $*CCSTATE := $s;
            }
            self;
        }

        # (must not allow anything to match . in nibbler or we'll lose track of state)
        token escape:ws { \s+ [ <?[#]> <.ws> ]? }
        token escape:sym<#> { '#' <.panic: "Please backslash # for literal char or put whitespace in front for comment"> }
        token escape:sym<\\> { <sym> <item=.backslash> <.ccstate('\\' ~ $<item>)> }
        token escape:sym<..> { <sym>
            [
            || <?{ ($*CCSTATE eq '') || ($*CCSTATE eq '..') }> <.sorry("Range missing start character on the left")>
            || <?before \s* <!stopper> <!before '..'> \S >
            || <.sorry("Range missing stop character on the right")>
            ]
            { $*CCSTATE := '..'; }
        }

        token escape:sym<-> {
            '-' <?{ $*CCSTATE ne '' }> \s* <!stopper> \S
            <.obs('- as character range','.. (or \\- if you mean a literal hyphen)')>
        }
        token escape:ch { $<ch> = [\S] { self.ccstate($<ch>) } }

        token backslash:delim { <text=.starter> | <text=.stopper> }
        token backslash:<\\> { <text=.sym> }
        token backslash:sym<a> { :i <sym> }
        token backslash:sym<b> { :i <sym> }
        token backslash:sym<c> { :i <sym> <charspec> }
        token backslash:sym<d> { :i <sym> { $*CCSTATE := '' } }
        token backslash:sym<e> { :i <sym> }
        token backslash:sym<f> { :i <sym> }
        token backslash:sym<h> { :i <sym> { $*CCSTATE := '' } }
        token backslash:sym<N> { <?before 'N{'<[A..Z]>> <.obs('\N{CHARNAME}','\c[CHARNAME]')>  }
        token backslash:sym<n> { :i <sym> }
        token backslash:sym<o> { :i :dba('octal character') <sym> [ <octint> | '[' ~ ']' <octints> | '{' <.obsbrace> ] }
        token backslash:sym<r> { :i <sym> }
        token backslash:sym<s> { :i <sym> { $*CCSTATE := '' } }
        token backslash:sym<t> { :i <sym> }
        token backslash:sym<v> { :i <sym> { $*CCSTATE := '' } }
        token backslash:sym<w> { :i <sym> { $*CCSTATE := '' } }
        token backslash:sym<x> { :i :dba('hex character') <sym> [ <hexint> | '[' ~ ']' <hexints> | '{' <.obsbrace> ] }
        token backslash:sym<0> { <sym> }

        # keep random backslashes like qq does
        token backslash:misc { {}
            [
            | $<text>=(\W)
            | $<x>=(\w) <.sorry("Unrecognized backslash sequence: '\\" ~ $<x> ~ "'")>
            ]
        }
        multi method tweak_q($v) { self.panic("Too late for :q") }
        multi method tweak_qq($v) { self.panic("Too late for :qq") }
        multi method tweak_cc($v) { self.panic("Too late for :cc") }
    }

    method truly($bool, $opt) {
        self.sorry("Cannot negate $opt adverb") unless $bool;
        self;
    }

    method apply_tweak($role) {
        my $target := nqp::can(self, 'herelang') ?? self.herelang !! self;
        $target.HOW.mixin($target, $role);
        self
    }

    method tweak_q($v)          { self.truly($v, ':q'); self.apply_tweak(Perl6::QGrammar::q) }
    method tweak_single($v)     { self.tweak_q($v) }
    method tweak_qq($v)         { self.truly($v, ':qq'); self.apply_tweak(Perl6::QGrammar::qq); }
    method tweak_double($v)     { self.tweak_qq($v) }

    method tweak_b($v)          { self.apply_tweak($v ?? b1 !! b0) }
    method tweak_backslash($v)  { self.tweak_b($v) }
    method tweak_s($v)          { self.apply_tweak($v ?? s1 !! s0) }
    method tweak_scalar($v)     { self.tweak_s($v) }
    method tweak_a($v)          { self.apply_tweak($v ?? a1 !! a0) }
    method tweak_array($v)      { self.tweak_a($v) }
    method tweak_h($v)          { self.apply_tweak($v ?? h1 !! h0) }
    method tweak_hash($v)       { self.tweak_h($v) }
    method tweak_f($v)          { self.apply_tweak($v ?? f1 !! f0) }
    method tweak_function($v)   { self.tweak_f($v) }
    method tweak_c($v)          { self.apply_tweak($v ?? c1 !! c0) }
    method tweak_closure($v)    { self.tweak_c($v) }

    method add-postproc(str $newpp) {
        my $target := nqp::can(self, 'herelang') ?? self.herelang !! self;

        my @pplist := nqp::can($target, "postprocessors")
            ?? $target.postprocessors
            !! nqp::list_s();
        nqp::push_s(@pplist, $newpp);

        # yes, the currying is necessary. Otherwise weird things can happen,
        # e.g.  perl6 -e 'q:w:x//; q:ww:v//' turning the second into q:w:x:v//
        role postproc[@curlist] {
            method postprocessors() {
                @curlist;
            }
        }
        $target.HOW.mixin($target, postproc.HOW.curry(postproc, @pplist));
        self
    }

# path() NYI
#    method tweak_p($v)          { $v ?? self.add-postproc("path") !! self }
#    method tweak_path($v)       { self.tweak_p($v) }

    method tweak_x($v)          { $v ?? self.add-postproc("run") !! self }
    method tweak_exec($v)       { self.tweak_x($v) }
    method tweak_w($v)          { $v ?? self.add-postproc("words") !! self }
    method tweak_words($v)      { self.tweak_w($v) }
    method tweak_ww($v)         { $v ?? self.add-postproc("quotewords").apply_tweak(ww) !! self }
    method tweak_quotewords($v) { self.tweak_ww($v) }

    method tweak_v($v)          { $v ?? self.add-postproc("val") !! self }
    method tweak_val($v)        { self.tweak_v($v) }

    method tweak_cc($v)         { self.truly($v, ':cc'); self.apply_tweak(cc); }

    method tweak_to($v) {
        self.truly($v, ':to');
        # the cursor_init is to ensure it's been initalized the same way
        # 'self' was back in quote_lang
        %*LANG<Quote>.HOW.mixin(%*LANG<Quote>, to.HOW.curry(to, self)).'!cursor_init'(self.orig(), :p(self.pos()), :shared(self.'!shared'()))
    }
    method tweak_heredoc($v)    { self.tweak_to($v) }

    method tweak_regex($v) {
        self.truly($v, ':regex');
        return %*LANG<Regex>;
    }
}

my role CursorPackageNibbler {
    method nibble-in-cursor($parent) {
        my $*PACKAGE := $*W.find_symbol(['Cursor']);
        my %*ATTR_USAGES;
        my $cur := nqp::findmethod($parent, 'nibbler')(self);
        for %*ATTR_USAGES {
            my $name := $_.key;
            my $node := $_.value[0].node;
            $node.CURSOR.typed_sorry('X::Attribute::Regex', symbol => $name);
        }
        $cur
    }
}

grammar Perl6::RegexGrammar is QRegex::P6Regex::Grammar does STD does CursorPackageNibbler {
    method nibbler() {
        self.nibble-in-cursor(QRegex::P6Regex::Grammar)
    }

    method throw_unrecognized_metachar ($metachar) {
        self.typed_sorry('X::Syntax::Regex::UnrecognizedMetachar', :$metachar);
    }
    method throw_null_pattern() {
        self.typed_sorry('X::Syntax::Regex::NullRegex');
    }
    method throw_unrecognized_regex_modifier($modifier) {
        self.typed_panic('X::Syntax::Regex::UnrecognizedModifier', :$modifier);
    }

    method throw_malformed_range() { self.typed_sorry('X::Syntax::Regex::MalformedRange') }
    method throw_confused() { self.typed_sorry('X::Syntax::Confused') }
    method throw_unspace($char) { self.typed_sorry('X::Syntax::Regex::Unspace', :$char) }
    method throw_regex_not_terminated() { self.typed_sorry('X::Syntax::Regex::Unterminated') }
    method throw_spaces_in_bare_range() { self.typed_sorry('X::Syntax::Regex::SpacesInBareRange') }
    method throw_non_quantifiable() { self.typed_sorry('X::Syntax::Regex::NonQuantifiable') }
    method throw_solitary_quantifier() { self.typed_sorry('X::Syntax::Regex::SolitaryQuantifier') }
    method throw_solitary_backtrack_control() { self.typed_sorry('X::Syntax::Regex::SolitaryBacktrackControl') }

    token normspace { <?before \s | '#'> <.LANG('MAIN', 'ws')> }

    token rxstopper { <stopper> }

    token metachar:sym<:my> {
        ':' <?before 'my'|'constant'|'state'|'our'|'temp'|'let'> <statement=.LANG('MAIN', 'statement')>
        <!RESTRICTED>
        <.LANG('MAIN', 'eat_terminator')>
    }

    token metachar:sym<{ }> {
        <?[{]> <codeblock>
    }

    token metachar:sym<rakvar> {
        <?before <sigil> $<twigil>=[<alpha> | \W<alpha> | '(']>
        <!before <sigil> <rxstopper> >
        <var=.LANG('MAIN', 'variable')>
        [
        || $<binding> = ( \s* '=' \s* <quantified_atom> )
           { self.check_variable($<var>) unless $<twigil> eq '<' }
        || { self.check_variable($<var>) }
           [ <?before '.'? <[ \[ \{ \< ]>> <.worry: "Apparent subscript will be treated as regex"> ]?
        ]
        <.SIGOK>
    }

    token metachar:sym<qw> {
        <?before '<' \s >  # (note required whitespace)
        '<' <nibble(self.quote_lang(%*LANG<Quote>, "<", ">", ['q', 'w']))> '>'
        <.SIGOK>
    }

    token metachar:sym<'> { <?[ ' " ‘ ‚ ’ “ „ ” ｢ ]> <quote=.LANG('MAIN','quote')> <.SIGOK> }

    token metachar:sym<{}> { \\<[xo]>'{' <.obsbrace> }

    token backslash:sym<1> { <[1..9]>\d* {} <.sorry("Unrecognized backslash sequence (did you mean \${$/ - 1}?)")> }

    token assertion:sym<{ }> {
        <?[{]> <codeblock>
    }

    token assertion:sym<?{ }> {
        '?' <?before '{'> <codeblock>
    }

    token assertion:sym<!{ }> {
        '!' <?before '{'> <codeblock>
    }

    token assertion:sym<var> {
        [
        | <?[&]> <!RESTRICTED> <var=.LANG('MAIN', 'term:sym<variable>')>
            [
            | ':' <arglist>
            | '(' <arglist> ')'
            ]?
        | <?sigil> <!RESTRICTED> <var=.LANG('MAIN', 'term:sym<variable>')>
        ]
    }

    token assertion:sym<~~> {
        <sym>
        <!RESTRICTED>
        [ <?[>]> | $<num>=[\d+] | <desigilname=.LANG('MAIN','desigilname')> ]
    }

    token codeblock {
        :my $*ESCAPEBLOCK := 1;
        <!RESTRICTED>
        <block=.LANG('MAIN','block')>
    }

    token arglist {
        :my $*IN_REGEX_ASSERTION := 1;
        <!RESTRICTED>
        <arglist=.LANG('MAIN','arglist')>
    }

    token assertion:sym<name> {
        <longname=.LANG('MAIN','longname')>
            [
            | <?[>]>
            | '=' <assertion>
            | ':' <arglist>
            | '(' <arglist> ')'
            | <.normspace> <nibbler>
            ]?
    }
}

grammar Perl6::P5RegexGrammar is QRegex::P5Regex::Grammar does STD does CursorPackageNibbler {
    method nibbler() {
        self.nibble-in-cursor(QRegex::P5Regex::Grammar)
    }

    token rxstopper { <stopper> }

    token p5metachar:sym<(?{ })> {
        '(?' <?[{]> <codeblock> ')'
    }

    token p5metachar:sym<(??{ })> {
        '(??' <?[{]> <codeblock> ')'
    }

    token p5metachar:sym<var> {
        <?[$]> <var=.LANG('MAIN', 'variable')>
    }

    token codeblock {
        :my $*ESCAPEBLOCK := 1;
        <block=.LANG('MAIN','block')>
    }
}

# vim: ft=perl6 et sw=4
