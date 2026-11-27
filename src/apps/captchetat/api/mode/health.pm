#
# Copyright 2026-Present Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::captchetat::api::mode::health;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::constants qw(:counters :values);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub custom_captchetat_status_output {
    my ($self, %options) = @_;
    
    return sprintf(
        "CaptchEtat status: %s",
        $self->{result_values}->{captchEtatStatus}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => COUNTER_TYPE_GLOBAL, skipped_code => { NO_VALUE() => 1 } }
    ];

    $self->{maps_counters}->{global} = [
        {
            label => 'captchetat-status',
            type => COUNTER_KIND_TEXT,
            critical_default => '%{captchEtatStatus} !~ /UP/',
            set => {
                key_values => [ { name => 'captchEtatStatus' } ],
                closure_custom_output => $self->can('custom_captchetat_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1);
    bless $self, $class;
    
    $options{options}->add_options(arguments => {
    });

    return $self;
}

sub manage_selection {
    my ($self, %options) = @_;

    my $health = $options{custom}->get_healthcheck();

    $self->{global} = {
        captchEtatStatus => defined($health->{components}->{captchaTestHealth}->{status}) ? $health->{components}->{captchaTestHealth}->{status} : 'unknown'
    };
}

1;

__END__

=head1 MODE

Check CaptchEtat status.

=over 8

=item B<--unknown-captchetat-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: %{captchEtatStatus}

=item B<--warning-captchetat-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: %{captchEtatStatus}

=item B<--critical-captchetat-status>

Define the conditions to match for the status to be CRITICAL (default: '%{captchEtatStatus} !~ /UP/').
You can use the following variables: %{captchEtatStatus}

=back

=cut