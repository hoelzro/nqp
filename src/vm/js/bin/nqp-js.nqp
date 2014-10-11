#use QAST;
use HLL::Backend;

sub MAIN(*@ARGS) {
    # Get original compiler, then re-register it as a cross compiler.
    my $nqpcomp-orig := nqp::getcomp('nqp');
    my $nqpcomp-cc   := nqp::clone($nqpcomp-orig);
    $nqpcomp-cc.language('nqp-cc');
    
    $nqpcomp-cc.backend(HLLBackend::JavaScript);
    
    #:custom-regex-lib('QRegex')

    $nqpcomp-cc.command_line(@ARGS, :stable-sc(1),:module-path('gen/js/stage2'),
        :setting-path('gen/js/stage2'),
        :custom-regex-lib('QRegex'),
        :setting('NQPCORE'), :no-regex-lib(0),
        :encoding('utf8'), :transcode('ascii iso-8859-1'));
}
