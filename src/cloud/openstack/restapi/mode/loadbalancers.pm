#
# Copyright 2025 Centreon (http://www.centreon.com/)
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

package cloud::openstack::restapi::mode::loadbalancers;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

sub custom_health_output {
    my ($self, %options) = @_;

    return sprintf(
        'operating status: %s [provisioning status: %s]',
        $self->{result_values}->{operatingStatus},
        $self->{result_values}->{provisioningStatus}
    );
}

sub custom_counter_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel},
        instances => $instances,
        value => $self->{result_values}->{ $self->{key_values}->[0]->{name} },
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0
    );
}

sub custom_traffic_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel},
        unit => 'b/s',
        instances => $instances,
        value => $self->{result_values}->{ $self->{key_values}->[0]->{name} },
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0
    );
}


sub prefix_connection_output {
    my ($self, %options) = @_;

    return 'number of connections ';
}

sub lb_long_output {
    my ($self, %options) = @_;

    return sprintf(
        "checking load balancer '%s' [project: %s]",
        $options{instance_value}->{lbName},
        $options{instance_value}->{projectName}
    );
}

sub prefix_lb_output {
    my ($self, %options) = @_;

    return sprintf(
        "load balancer '%s' [project: %s] ",
        $options{instance_value}->{lbName},
        $options{instance_value}->{projectName}
    );
}

sub prefix_global_output {
    my ($self, %options) = @_;

    return 'Number of load balancers ';
}

sub prefix_project_output {
    my ($self, %options) = @_;

    return sprintf(
        "Project '%s' number of load balancers ",
        $options{instance_value}->{projectName}
    );
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => 0, cb_prefix_output => 'prefix_global_output' },
        { name => 'projects', type => 1, cb_prefix_output => 'prefix_project_output', message_multiple => 'All projects are ok', skipped_code => { -10 => 1 } },
        {
            name => 'lbs', type => 3, cb_prefix_output => 'prefix_lb_output', cb_long_output => 'lb_long_output', indent_long_output => '    ', message_multiple => 'All load balancers are ok',
            group => [
                { name => 'health', type => 0 },
                { name => 'connection', type => 0, cb_prefix_output => 'prefix_connection_output', },
                { name => 'error', type => 0 },
                { name => 'traffic', type => 0 }
            ]
        }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'lbs-detected', display_ok => 0, nlabel => 'loadbalancers.detected.count', set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'detected: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{projects} = [];
    foreach my $status (('online', 'draining', 'offline', 'degraded', 'error', 'no_monitor')) {
        my $status_help = $status;
        $status_help =~ s/_//g;
        push @{$self->{maps_counters}->{projects}},
            {
                label => 'project-lbs-opstatus-' . $status_help, display_ok => 0, nlabel => 'project.loadbalancers.operating_status.' . $status . '.count',
                set => {
                    key_values => [ { name => $status }, { name => 'total' }, { name => 'projectName' } ],
                    output_template => $status . ': %s',
                    perfdatas => [
                        { template => '%s', min => 0, max => 'total', label_extra_instance => 1, instance_use => 'projectName' }
                    ]
                }
            };
    }

    $self->{maps_counters}->{health} = [
        {
            label => 'health',
            type => 2,
            unknown_default => '%{provisioningStatus} =~ /active/i and %{operatingStatus} =~ /no_monitor/i',
            warning_default => '%{provisioningStatus} =~ /active/i and %{operatingStatus} =~ /degraded/i',
            critical_default => '%{provisioningStatus} =~ /error/i or %{operatingStatus} =~ /error/i',
            set => {
                key_values => [ { name => 'operatingStatus' },  { name => 'provisioningStatus' }, { name => 'lbName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_health_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        }
    ];

    $self->{maps_counters}->{connection} = [
        { label => 'connections-active', nlabel => 'loadbalancer.connections.active.count', set => {
                key_values => [ { name => 'active' }, { name => 'lbName' }, { name => 'projectName' } ],
                output_template => 'active: %s',
                closure_custom_perfdata => $self->can('custom_counter_perfdata')
            }
        },
        { label => 'connections-total', nlabel => 'loadbalancer.connections.total.count', set => {
                key_values => [ { name => 'total', diff => 1 }, { name => 'lbName' }, { name => 'projectName' } ],
                output_template => 'total: %s',
                closure_custom_perfdata => $self->can('custom_counter_perfdata')
            }
        }
    ];

    $self->{maps_counters}->{error} = [
        { label => 'requests-error', nlabel => 'loadbalancer.requests.error.count', set => {
                key_values => [ { name => 'total', diff => 1 }, { name => 'lbName' }, { name => 'projectName' } ],
                output_template => 'number of requests in error: %s',
                closure_custom_perfdata => $self->can('custom_counter_perfdata')
            }
        }
    ];

    $self->{maps_counters}->{traffic} = [
        { label => 'traffic-in', nlabel => 'loadbalancer.traffic.in.bitspersecond', set => {
                key_values => [ { name => 'in', per_second => 1 }, { name => 'lbName' }, { name => 'projectName' } ],
                output_template => 'traffic in: %s %s/s',
                output_change_bytes => 2,
                closure_custom_perfdata => $self->can('custom_traffic_perfdata')
            }
        },
        { label => 'traffic-out', nlabel => 'loadbalancer.traffic.out.bitspersecond', set => {
                key_values => [ { name => 'out', per_second => 1 }, { name => 'lbName' }, { name => 'projectName' } ],
                output_template => 'traffic out: %s %s/s',
                output_change_bytes => 2,
                closure_custom_perfdata => $self->can('custom_traffic_perfdata')
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, statefile => 1, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => { 
        'filter-project-name:s' => { name => 'filter_project_name' },
        'filter-lb-name:s'      => { name => 'filter_lb_name' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (!defined($self->{option_results}->{custom_perfdata_instances}) || $self->{option_results}->{custom_perfdata_instances} eq '') {
        $self->{option_results}->{custom_perfdata_instances} = '%(projectName) %(lbName)';
    }

    $self->{custom_perfdata_instances} = $self->custom_perfdata_instances(
        option_name => '--custom-perfdata-instances',
        instances => $self->{option_results}->{custom_perfdata_instances},
        labels => { projectName => 1, lbName => 1 }
    );
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{global} = { detected => 0 };
    $self->{projects} = {};
    $self->{lbs} = {};

    my $projects = $options{custom}->get_projects();
    foreach my $project (@$projects) {
        next if (defined($self->{option_results}->{filter_project_name}) && $self->{option_results}->{filter_project_name} ne '' &&
            $project->{name} !~ /$self->{option_results}->{filter_project_name}/);

        if (!defined($self->{projects}->{ $project->{id} })) {
            $self->{projects}->{ $project->{id} } = {
                projectName => $project->{name},
                online => 0, draining => 0, offline => 0, 
                degraded => 0, error => 0, no_monitor => 0,
                total => 0
            };
        }

        my $lbs = $options{custom}->get_loadbalancers(project_id => $project->{id});
        
        foreach my $lb (@$lbs) {
            next if (defined($self->{option_results}->{filter_lb_name}) && $self->{option_results}->{filter_lb_name} ne '' &&
               $lb->{name} !~ /$self->{option_results}->{filter_lb_name}/);

            $self->{lbs}->{ $project->{id} . $lb->{id} } = {
                lbName => $lb->{name},
                projectName => $project->{name},
                health => {
                    lbName => $lb->{name},
                    projectName => $project->{name},
                    operatingStatus => lc($lb->{operating_status}),
                    provisioningStatus => lc($lb->{provisioning_status})
                },
                connection => {
                    lbName => $lb->{name},
                    projectName => $project->{name},
                },
                error => {
                    lbName => $lb->{name},
                    projectName => $project->{name},
                },
                traffic => {
                    lbName => $lb->{name},
                    projectName => $project->{name},
                }
            };

            my $stats = $options{custom}->get_loadbalancer_stats(project_id => $project->{id}, lb_id => $lb->{id});
            $self->{lbs}->{ $project->{id} . $lb->{id} }->{connection}->{active} = $stats->[0]->{active_connections};
            $self->{lbs}->{ $project->{id} . $lb->{id} }->{connection}->{total} = $stats->[0]->{total_connections};

            $self->{lbs}->{ $project->{id} . $lb->{id} }->{error}->{total} = $stats->[0]->{request_errors};

            $self->{lbs}->{ $project->{id} . $lb->{id} }->{traffic}->{in} = $stats->[0]->{bytes_in};
            $self->{lbs}->{ $project->{id} . $lb->{id} }->{traffic}->{out} = $stats->[0]->{bytes_out};

            $self->{projects}->{ $project->{id} }->{ lc($lb->{operating_status}) }++;
            $self->{projects}->{ $project->{id} }->{total}++;
            $self->{global}->{detected}++;
        }
    }

    $self->{cache_name} = 'openstack_' . $self->{mode} . '_' .
        md5_hex(
            $options{custom}->get_connection_info() . '_' .
            (defined($self->{option_results}->{filter_counters}) ? md5_hex($self->{option_results}->{filter_counters}) : '') . '_' .
            (defined($self->{option_results}->{filter_project_name}) ? md5_hex($self->{option_results}->{filter_project_name}) : '') . '_' .
            (defined($self->{option_results}->{filter_lb_name}) ? md5_hex($self->{option_results}->{filter_lb_name}) : '')
        );
}

1;

__END__

=head1 MODE

Check load balancers.

=over 8

=item B<--filter-project-name>

Filter load balancers by project name.

=item B<--filter-lb-name>

Filter load balancers by load balancer name.

=item B<--custom-perfdata-instances>

Define perfdatas instance (default: '%(projectName) %(lbName)')

=item B<--unknown-health>

Define the conditions to match for the status to be UNKNOWN (default: '%{provisioningStatus} =~ /active/i and %{operatingStatus} =~ /no_monitor/i').
You can use the following variables: %{operatingStatus}, %{provisioningStatus}, %{lbName}, %{projectName}

=item B<--warning-health>

Define the conditions to match for the status to be WARNING (default: '%{provisioningStatus} =~ /active/i and %{operatingStatus} =~ /degraded/i').
You can use the following variables: %{operatingStatus}, %{provisioningStatus}, %{lbName}, %{projectName}

=item B<--critical-health>

Define the conditions to match for the status to be CRITICAL (default: '%{provisioningStatus} =~ /error/i or %{operatingStatus} =~ /error/i').
You can use the following variables: %{operatingStatus}, %{provisioningStatus}, %{lbName}, %{projectName}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'lbs-detected', 'connections-active', 'connections-total',
'requests-error', 'traffic-in', 'traffic-out',
'project-lbs-opstatus-active', 'project-lbs-opstatus-draining', 'project-lbs-opstatus-offline',
'project-lbs-opstatus-degraded', 'project-lbs-opstatus-error', 'project-lbs-opstatus-nomonitor'.

=back

=cut
