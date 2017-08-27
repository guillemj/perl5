package Haiku;

BEGIN {
    use strict;

    use Exporter qw(import);
    require DynaLoader;

    our @ISA = qw|DynaLoader|;
    our $VERSION = '0.35';
    our $XS_VERSION = $VERSION;
    $VERSION = eval $VERSION;

    our @EXPORT = qw(
    );
    our @EXPORT_OK = qw(
    );
}

bootstrap Haiku;

1;

__END__

=head1 NAME

Haiku - Interfaces to some Haiku API Functions

=head1 DESCRIPTION

The Haiku module contains functions to access Haiku APIs.

=head2 Alphabetical Listing of Haiku Functions

=over

=item Haiku::debug_printf(FORMAT,...)

Similar to printf, but prints to system debug output.

=item Haiku::debugger(FORMAT,...)

Drops the program into the debugger. The printf like arguments define the
debugger message.

=item Haiku::ktrace_printf(FORMAT,...)

Similar to printf, but prints to a kernel tracing entry.

=back

=cut
