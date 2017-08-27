package Testing;
use 5.006_001;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(_dumptostr);
use Carp;

sub _dumptostr {
    my ($obj) = @_;
    return join '', $obj->Dump;
}

1;
