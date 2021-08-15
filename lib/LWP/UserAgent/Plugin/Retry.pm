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
    my ($class, $r) = @_;

    $r->{config}{max_attempts} //=
        $ENV{LWP_USERAGENT_PLUGIN_RETRY_MAX_ATTEMPTS} // 4;
    $r->{config}{delay}        //=
        $ENV{LWP_USERAGENT_PLUGIN_RETRY_DELAY}        // 2;
    if (defined $r->{config}{strategy}) {
        require Module::Load::Util;
        $r->{ua}{_backoff_obj} //=
            Module::Load::Util::instantiate_class_with_optional_args(
                {ns_prefix => 'Algorithm::Backoff'}, $r->{config}{strategy});
    }

    my $is_success;
    my $code = $r->{response}->code;
    if (defined $r->{config}{retry_if}) {
        my $ref = ref $r->{config}{retry_if};
        if ($ref eq 'Regexp' or !$ref) {
            $is_success++ unless $code =~ $r->{config}{retry_if};
        } elsif ($ref eq 'ARRAY') {
            $is_success++ unless grep { $_ == $code } @{ $r->{config}{retry_if} };
        } elsif ($ref eq 'CODE') {
            $is_success++ unless $r->{config}{retry_if}->($class, $r);
        } else {
            die "Please supply a scalar/Regexp/arrayref/coderef retry_if";
        }
    } else {
        $is_success++ if $code !~ /\A[5]/;
    }

  SUCCESS: {
        last unless $is_success;
        if ($r->{ua}{_backoff_obj}) {
            my $delay_on_success = $r->{ua}{_backoff_obj}->success;
            if ($delay_on_success > 0) {
                log_trace "Delaying for %.1f second(s) after successful request", $delay_on_success;
                sleep $delay_on_success;
            }
        }
        return -1;
    }

    $r->{retries} //= 0;
    my $max_attempts;
    my $delay;
    my $should_give_up;
    if ($r->{ua}{_backoff_obj}) {
        $delay = $r->{ua}{_backoff_obj}->failure;
        $should_give_up++ if $delay < 0;
        $max_attempts = $r->{ua}{_backoff_obj}{max_attempts};
    } else {
        $should_give_up++ if $r->{config}{max_attempts} &&
            1+$r->{retries} >= $r->{config}{max_attempts};
        $max_attempts = $r->{config}{max_attempts};
        $delay = $r->{config}{delay};
    }

    my ($ua, $request) = @{ $r->{argv} };

  GIVE_UP: {
        last unless $should_give_up;
        log_trace "Failed requesting %s %s (%s - %s), giving up",
        $request->method,
        $request->uri . "",
        $r->{response}->code,
        $r->{response}->message;
        return 0;
    }

    $r->{retries}++;

    log_trace "Failed requesting %s %s (%s - %s), retrying in %.1f second(s) (attempt %d of %d) ...",
        $request->method,
        $request->uri . "",
        $r->{response}->code,
        $r->{response}->message,
        $delay,
        1+$r->{retries},
        $max_attempts;
    sleep $delay;
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

 my $res  = LWP::UserAgent::Plugin->new->get("http://www.example.com/");


=head1 DESCRIPTION

This plugin retries failed response. By default only retries 5xx failures, as
4xx are considered to be client's fault (but you can configure it with
L</retry_if>).


=head1 CONFIGURATION

=head2 max_attempts

Int. Default 4.

=head2 delay

Float.


=head1 ENVIRONMENT

=head2 LWP_USERAGENT_PLUGIN_RETRY_MAX_ATTEMPTS

Int.

=head2 LWP_USERAGENT_PLUGIN_RETRY_DELAY

Int.


=head1 SEE ALSO

L<LWP::UserAgent::Plugin>

Existing non-plugin solutions: L<LWP::UserAgent::Determined>,
L<LWP::UserAgent::ExponentialBackoff>.

Equivalent plugin for L<HTTP::Tiny::Plugin>: L<HTTP::Tiny::Plugin::Retry>
