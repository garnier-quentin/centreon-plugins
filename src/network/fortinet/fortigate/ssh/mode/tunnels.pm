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

package network::fortinet::fortigate::ssh::mode::tunnels;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);
use centreon::plugins::constants qw(:counters);
use centreon::plugins::misc;
use DateTime;
use POSIX;

my $unitdiv = { s => 1, w => 604800, d => 86400, h => 3600, m => 60 };
my $unitdiv_long = { s => 'seconds', w => 'weeks', d => 'days', h => 'hours', m => 'minutes' };

sub custom_last_rule_used_perfdata {
    my ($self, %options) = @_;

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel} . '.' . $unitdiv_long->{ $self->{instance_mode}->{option_results}->{unit} },
        instances => $self->{result_values}->{tunnelName},
        unit => $self->{instance_mode}->{option_results}->{unit},
        value => $self->{result_values}->{lastRuleUsedSeconds} >= 0 ? floor($self->{result_values}->{lastRuleUsedSeconds} / $unitdiv->{ $self->{instance_mode}->{option_results}->{unit} }) : $self->{result_values}->{lastRuleUsedSeconds},
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0
    );
}

sub custom_last_rule_used_threshold {
    my ($self, %options) = @_;

    return $self->{perfdata}->threshold_check(
        value => $self->{result_values}->{lastRuleUsedSeconds} >= 0 ? floor($self->{result_values}->{lastRuleUsedSeconds} / $unitdiv->{ $self->{instance_mode}->{option_results}->{unit} }) : $self->{result_values}->{lastRuleUsedSeconds},
        threshold => [
            { label => 'critical-' . $self->{thlabel}, exit_litteral => 'critical' },
            { label => 'warning-'. $self->{thlabel}, exit_litteral => 'warning' },
            { label => 'unknown-'. $self->{thlabel}, exit_litteral => 'unknown' }
        ]
    );
}

sub custom_status_output {
    my ($self, %options) = @_;

    return sprintf(
        'primary path: %s, secondary path: %s',
        $self->{result_values}->{primaryPath},
        $self->{result_values}->{secondaryPath}
    );
}

sub tunnel_long_output {
    my ($self, %options) = @_;

    return sprintf(
        "checking tunnel '%s'",
        $options{instance_value}->{name}
    );
}

sub prefix_tunnel_output {
    my ($self, %options) = @_;

    return sprintf(
        "tunnel '%s' ",
        $options{instance_value}->{name}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        {
            name               => 'tunnels',
            type               => COUNTER_TYPE_MULTIPLE,
            cb_prefix_output   => 'prefix_tunnel_output',
            cb_long_output     => 'tunnel_long_output',
            indent_long_output => '    ',
            message_multiple   => 'All tunnels are ok',
            group              =>
                [
                    { name => 'global', type => COUNTER_MULTIPLE_INSTANCE, skipped_code => { NO_VALUE => 1 } },
                    { name => 'status', type => COUNTER_MULTIPLE_INSTANCE },
                    { name => 'rule', type => COUNTER_MULTIPLE_INSTANCE, skipped_code => { NO_VALUE => 1 } }
                ]
        }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'paths-count', nlabel => 'tunnels.paths.count', set => {
                key_values => [ { name => 'paths_count' } ],
                output_template => 'number of paths: %s',
                perfdatas => [
                    { template => '%d', min => 0, label_extra_instance => 1 }
                ]
            }
        }
    ];
 
    $self->{maps_counters}->{status} = [
        {
            label => 'tunnel-status', type => COUNTER_KIND_TEXT, critical_default => '%{primaryPath} !~ /_1/ or %{secondaryPath} !~ /_2/', set => {
            key_values                     =>
                [
                    { name => 'primaryPath' },
                    { name => 'secondaryPath' },
                    { name => 'tunnelName' }
                ],
            closure_custom_output          =>  $self->can('custom_status_output'),
            closure_custom_perfdata        => sub { return 0; },
            closure_custom_threshold_check => \&catalog_status_threshold_ng
        }
        }
    ];

     $self->{maps_counters}->{rule} = [
         { label => 'rule-used-last', nlabel => 'tunnel.rule.used.last', set => {
                key_values  => [ { name => 'lastRuleUsedSeconds' }, { name => 'lastRuleUsedHuman' }, { name => 'tunnelName' } ],
                output_template => 'last rule used %s',
                output_use => 'lastRuleUsedHuman',
                closure_custom_perfdata => $self->can('custom_last_rule_used_perfdata'),
                closure_custom_threshold_check => $self->can('custom_last_rule_used_threshold')
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'include-tunnel-name:s'  => { name => 'include_tunnel_name',  default => '' },
        'exclude-tunnel-name:s'  => { name => 'exclude_tunnel_name',  default => '' },
        'unit:s'             => { name => 'unit', default => 's' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if ($self->{option_results}->{unit} eq '' || !defined($unitdiv->{$self->{option_results}->{unit}})) {
        $self->{option_results}->{unit} = 's';
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    my ($stdout) = $options{custom}->execute_command(
        command => 'diagnose',
        command_options => 'firewall proute list'
    );

    $stdout =~ s/\x{0d}//g; # carriage return

    #id=2141847555(0x7faa0003) vwl_service=3(To_Montpellier-Admin) vwl_mbr_seq=7 8 dscp_tag=0xfc 0xfc flags=0x40 order-addr tos=0x00 tos_mask=0x00 protocol=0 port=src(0->0):dst(0->0) iif=0(any) 
    #path(2): oif=24(O_AdmC-M_1), oif=25(O_AdmC-M_2)
    #source wildcard(1): 0.0.0.0/0.0.0.0 
    #destination address(route_tag): 12 
    #hit_count=0 rule_last_used=2026-02-24 15:25:16

    my $ctime = time();
    $self->{tunnels} = {};
    while ($stdout =~ /^id=.*?vwl_service=\S+\((.*?)\).*?path.*?:\s*(.*?)\n.*?rule_last_used=(.*?)(?=\n\s*\n|\Z$)/msg) {
        my ($tunnel_name, $paths, $rule_last_used) = ($1, $2, $3);
 
        next if (centreon::plugins::misc::is_excluded($tunnel_name, $self->{option_results}->{include_tunnel_name}, $self->{option_results}->{exclude_tunnel_name}));
 
        my $path_names = ['none', 'none'];
        my $i = 0;
        while ($paths =~ /oif=\S+\((.*?)\)/msg) {
            $path_names->[$i] = $1;
            $i++;
        }
 
        $self->{tunnels}->{$tunnel_name} = {
            name           => $tunnel_name,
            global => {
                paths_count => $i
            },
            status => {
                tunnelName    => $tunnel_name,
                primaryPath   => $path_names->[0],
                secondaryPath => $path_names->[1]
            }
        };

        if ($rule_last_used =~ /^\s*(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)/) {
            my $dt = DateTime->new(year => $1, month => $2, day => $3, hour => $4, minute => $5, second => $6);
            $self->{tunnels}->{$tunnel_name}->{rule} = {
                tunnelName => $tunnel_name,
                lastRuleUsedSeconds => $ctime - $dt->epoch()
            };
            $self->{tunnels}->{$tunnel_name}->{rule}->{lastRuleUsedHuman} = centreon::plugins::misc::change_seconds(value => $self->{tunnels}->{$tunnel_name}->{rule}->{lastRuleUsedSeconds});
        }
    }

    if (scalar(keys %{$self->{tunnels}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "Couldn't get tunnel information");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check tunnels.

=over 8

=item B<--filter-counters>

Define which counters (filtered by regular expression) should be monitored.
Can be : paths-count tunnel-status
Example: --filter-counters='tunnel-status'

=item B<--include-tunnel-name>

Include tunnel names (regexp).

=item B<--exclude-tunnel-name>

Exclude tunnel names (regexp).

=item B<--unit>

Select the time unit for the last rule used time thresholds. May be 's' for seconds, 'm' for minutes, 'h' for hours, 'd' for days, 'w' for weeks. Default is secondss.

=item B<--warning-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: C<%{primaryPath}>, C<%{secondaryPath}>, C<%{tunnelName}>

=item B<--critical-status>

Define the conditions to match for the status to be CRITICAL (default: C<'%{primaryPath} !~ /_1/ or %{secondaryPath} !~ /_2/'>).
You can use the following variables: C<%{primaryPath}>, C<%{secondaryPath}>, C<%{tunnelName}>

=item B<--warning-paths-count>

Warning threshold for number of tunnel paths active.

=item B<--critical-paths-count>

Critical threshold for number of tunnel paths active.

=back

=cut
