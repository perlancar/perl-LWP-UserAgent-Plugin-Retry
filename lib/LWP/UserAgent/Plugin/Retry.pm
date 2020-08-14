package LWP::UserAgent::Plugin::Retry;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Time::HiRes qw(sleep);

sub after_request {
    my ($self, $r) = @_;

    $r->{config}{max_attempts} //=
        $ENV{LWP_USERAGENT_PLUGIN_RETRY_MAX_ATTEMPTS} // 3;
    $r->{config}{delay}        //=
        $ENV{LWP_USERAGENT_PLUGIN_RETRY_DELAY}        // 2;

    my $should_retry = 0;
    if (($r->{config}{retry_client_errors} // 0) && $r->{response}->code =~ /\A4/) { $should_retry++ }
    if (($r->{config}{retry_server_errors} // 1) && $r->{response}->code =~ /\A5/) { $should_retry++ }
    return -1 unless $should_retry;

    $r->{retries} //= 0;
    return 0 if $r->{config}{max_attempts} &&
        $r->{retries} >= $r->{config}{max_attempts};
    $r->{retries}++;
    my ($ua, $request) = @{ $r->{argv} };
    log_trace "Failed requesting %s (%s - %s), retrying in %.1f second(s) (%d of %d) ...",
        $request->uri,
        $r->{response}->code,
        $r->{response}->message,
        $r->{config}{delay},
        $r->{retries},
        $r->{config}{max_attempts};
    sleep $r->{config}{delay};
    98; # repeat request()
}

1;
# ABSTRACT: Retry failed requests

=for Pod::Coverage .+

=head1 SYNOPSIS

 use LWP::UserAgent::Plugin 'Retry' => {
     max_attempts => 3, # optional, default 3
     delay        => 2, # optional, default 2
     retry_if     => qr/^[45]/, # optional, default is only 5xx errors are retried
 };

 my $res  = HTTP::Tiny::Plugin->new->get("http://www.example.com/");


=head1 DESCRIPTION

This plugin retries failed response. By default only retries 5xx failures, as
4xx are considered to be client's fault (but you can configure it with
L</retry_if>).


=head1 CONFIGURATION

=head2 max_attempts

Int.

=head2 delay

Float.

=head2 retry_client_errors

Bool, default 0. Whether 4xx errors should be retried.

=head2 retry_server_errors

Bool, default 1. Whether 5xx errors should be retried.


=head1 ENVIRONMENT

=head2 LWP_USERAGENT_PLUGIN_RETRY_MAX_ATTEMPTS

Int.

=head2 LWP_USERAGENT_PLUGIN_RETRY_DELAY

Int.


=head1 SEE ALSO

L<LWP::UserAgent::Plugin>

L<LWP::UserAgent::Plugin::CustomRetry> uses L<Algorithm::Backoff> to give you
several retry delay strategies.

Existing non-plugin solutions: L<LWP::UserAgent::Determined>,
L<LWP::UserAgent::ExponentialBackoff>.

Equivalent plugin for L<HTTP::Tiny::Plugin>: L<HTTP::Tiny::Plugin::Retry>
