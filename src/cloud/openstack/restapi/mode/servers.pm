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

package cloud::openstack::restapi::mode::servers;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use Time::HiRes;
use Digest::MD5 qw(md5_hex);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold_ng);

my $map_power_state = {
    0 => 'noState', 
    1 => 'running', 
    3 => 'paused', 
    4 => 'shutdown', 
    6 => 'crashed', 
    7 => 'suspended'
};

sub custom_cpu_calc {
    my ($self, %options) = @_;

    if (!defined($options{old_datas}->{$self->{instance} . '_cpuTime'})) {
        $self->{error_msg} = "Buffer creation";
        return -1;
    }

    $self->{result_values}->{cpuUtil} =
        ($options{new_datas}->{$self->{instance} . '_cpuTime'} -
         $options{old_datas}->{$self->{instance} . '_cpuTime'}) * 100 /
        ($options{new_datas}->{$self->{instance} . '_deltaTime'} -
         $options{old_datas}->{$self->{instance} . '_deltaTime'});
    $self->{result_values}->{cpuId} = $options{new_datas}->{$self->{instance} . '_cpuId'};
    $self->{result_values}->{domainName} = $options{new_datas}->{$self->{instance} . '_domainName'};
    $self->{result_values}->{serverName} = $options{new_datas}->{$self->{instance} . '_serverName'};
    $self->{result_values}->{projectName} = $options{new_datas}->{$self->{instance} . '_projectName'};

    return 0;
}

sub custom_memory_output {
    my ($self, %options) = @_;

    my ($total_size_value, $total_size_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{total});
    my ($total_used_value, $total_used_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{used});
    my ($total_free_value, $total_free_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{free});
    return sprintf(
        'memory usage total: %s used: %s (%.2f%%) free: %s (%.2f%%)',
        $total_size_value . " " . $total_size_unit,
        $total_used_value . " " . $total_used_unit, $self->{result_values}->{prct_used},
        $total_free_value . " " . $total_free_unit, $self->{result_values}->{prct_free}
    );
}

sub custom_memory_detailed_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel},
        unit => 'B',
        instances => $instances,
        value => $self->{result_values}->{ $self->{key_values}->[0]->{name} },
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0,
        max => $self->{result_values}->{total}
    );
}

sub custom_cpu_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    push @$instances, $self->{result_values}->{cpuId};

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel},
        unit => '%',
        instances => $instances,
        value => $self->{result_values}->{cpuUtil},
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0,
        max => 100
    );
}

sub custom_traffic_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    push @$instances, $self->{result_values}->{macAddress};

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

sub custom_percent_perfdata {
    my ($self) = @_;

    my $instances = [];
    foreach (@{$self->{instance_mode}->{custom_perfdata_instances}}) {
        push @$instances, $self->{result_values}->{$_};
    }

    $self->{output}->perfdata_add(
        nlabel => $self->{nlabel},
        unit => '%',
        instances => $instances,
        value => $self->{result_values}->{ $self->{key_values}->[0]->{name} },
        warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $self->{thlabel}),
        critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $self->{thlabel}),
        min => 0,
        max => 100
    );
}

sub custom_port_output {
    my ($self, %options) = @_;

    return sprintf(
        'status: %s [network status: %s]',
        $self->{result_values}->{portStatus},
        $self->{result_values}->{networkStatus}
    );
}

sub custom_health_output {
    my ($self, %options) = @_;

    return sprintf(
        'state: %s [power state: %s]',
        $self->{result_values}->{vmState},
        $self->{result_values}->{powerState}
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

sub server_long_output {
    my ($self, %options) = @_;

    return sprintf(
        "checking server '%s' [project: %s]",
        $options{instance_value}->{serverName},
        $options{instance_value}->{projectName}
    );
}

sub prefix_server_output {
    my ($self, %options) = @_;

    return sprintf(
        "server '%s' [project: %s] ",
        $options{instance_value}->{serverName},
        $options{instance_value}->{projectName}
    );
}

sub prefix_global_output {
    my ($self, %options) = @_;

    return 'Number of servers ';
}

sub prefix_project_output {
    my ($self, %options) = @_;

    return sprintf(
        "Project '%s' number of servers ",
        $options{instance_value}->{projectName}
    );
}

sub prefix_port_output {
    my ($self, %options) = @_;

    return sprintf(
        "port '%s' [network: %s, mac address: %s] ",
        $options{instance_value}->{portId},
        $options{instance_value}->{networkName},
        $options{instance_value}->{macAddress}
    );
}

sub prefix_cpu_output {
    my ($self, %options) = @_;

    return "CPU '" . $options{instance_value}->{cpuId} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'global', type => 0, cb_prefix_output => 'prefix_global_output' },
        { name => 'projects', type => 1, cb_prefix_output => 'prefix_project_output', message_multiple => 'All projects are ok', skipped_code => { -10 => 1 } },
        {
            name => 'servers', type => 3, cb_prefix_output => 'prefix_server_output', cb_long_output => 'server_long_output', indent_long_output => '    ', message_multiple => 'All servers are ok',
            group => [
                { name => 'health', type => 0 },
                { name => 'cpu', display_long => 1, cb_prefix_output => 'prefix_cpu_output', message_multiple => 'all CPUs usage are ok', type => 1, skipped_code => { -10 => 1 } },
                { name => 'memory', type => 0, skipped_code => { -10 => 1 } },
                { name => 'ports', type => 1, cb_prefix_output => 'prefix_port_output', message_multiple => 'All ports are ok', skipped_code => { -10 => 1 } },
            ]
        }
    ];

    $self->{maps_counters}->{global} = [
        { label => 'servers-detected', display_ok => 0, nlabel => 'servers.detected.count', set => {
                key_values => [ { name => 'detected' } ],
                output_template => 'detected: %s',
                perfdatas => [
                    { template => '%s', min => 0 }
                ]
            }
        }
    ];

    $self->{maps_counters}->{projects} = [];
    foreach my $status (values %$map_power_state) {
        my $status_help = lc($status);
        push @{$self->{maps_counters}->{projects}},
            {
                label => 'project-servers-power-status-' . $status_help, display_ok => 0, nlabel => 'project.servers.power_status.' . $status . '.count',
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
            warning_default => '%{vmState} =~ /rescued/i',
            critical_default => '%{powerState} =~ /crashed/i or %{vmState} =~ /error/i',
            set => {
                key_values => [ { name => 'vmState' }, { name => 'powerState' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_health_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        }
    ];
 
    $self->{maps_counters}->{ports} = [
        {
            label => 'port-status',
            type => 2,
            critical_default => '%{networkStatus} =~ /down|error/i or %{portStatus} =~ /down|error/i',
            set => {
                key_values => [ { name => 'portStatus' }, { name => 'networkStatus' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_port_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold_ng
            }
        },
        { label => 'traffic-in', set => {
                key_values => [ { name => 'trafficIn', per_second => 1 }, { name => 'macAddress' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                output_template => 'traffic in: %s %s/s',
                output_change_bytes => 2,
                closure_custom_perfdata => $self->can('custom_traffic_perfdata')
            }
        },
        { label => 'traffic-out', set => {
                key_values => [ { name => 'trafficOut', per_second => 1 }, { name => 'macAddress' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                output_template => 'traffic out: %s %s/s',
                output_change_bytes => 2,
                closure_custom_perfdata => $self->can('custom_traffic_perfdata')
            }
        }
    ];

    $self->{maps_counters}->{memory} = [
        { label => 'memory-usage', nlabel => 'server.memory.usage.bytes', set => {
                key_values => [ { name => 'used' }, { name => 'free' }, { name => 'prct_used' }, { name => 'prct_free' }, { name => 'total' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_memory_output'),
                closure_custom_perfdata => $self->can('custom_memory_detailed_perfdata')
            }
        },
        { label => 'memory-usage-free', nlabel => 'server.memory.free.bytes', display_ok => 0, set => {
                key_values => [ { name => 'free' }, { name => 'used' }, { name => 'prct_used' }, { name => 'prct_free' }, { name => 'total' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_memory_output'),
                closure_custom_perfdata => $self->can('custom_memory_detailed_perfdata')
            }
        },
        { label => 'memory-usage-prct', nlabel => 'server.memory.usage.percentage', display_ok => 0, set => {
                key_values => [ { name => 'prct_used' }, { name => 'used' }, { name => 'free' }, { name => 'prct_free' }, { name => 'total' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_output => $self->can('custom_memory_output'),
                closure_custom_perfdata => $self->can('custom_percent_perfdata')
            }
        }
    ];

     $self->{maps_counters}->{cpu} = [
        { label => 'cpu-utilization', nlabel => 'server.core.cpu.utilization.percentage', set => {
                key_values => [ { name => 'cpuTime', diff => 1 }, { name => 'deltaTime', diff => 1 }, { name => 'cpuId' }, { name => 'domainName' }, { name => 'serverName' }, { name => 'projectName' } ],
                closure_custom_calc => $self->can('custom_cpu_calc'),
                output_template => 'usage: %.2f %%',
                threshold_use => 'cpuUtil',
                output_use => 'cpuUtil',
                closure_custom_perfdata => $self->can('custom_cpu_perfdata')
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, statefile => 1, force_new_perfdata => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => { 
        'filter-project-name:s'       => { name => 'filter_project_name' },
        'filter-server-name:s'        => { name => 'filter_server_name' },
        'custom-perfdata-instances:s' => { name => 'custom_perfdata_instances' },
        'add-stats'                   => { name => 'add_stats' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (!defined($self->{option_results}->{custom_perfdata_instances}) || $self->{option_results}->{custom_perfdata_instances} eq '') {
        $self->{option_results}->{custom_perfdata_instances} = '%(projectName) %(serverName)';
    }

    $self->{custom_perfdata_instances} = $self->custom_perfdata_instances(
        option_name => '--custom-perfdata-instances',
        instances => $self->{option_results}->{custom_perfdata_instances},
        labels => { domainName => 1, projectName => 1, serverName => 1 }
    );
}

sub add_stats {
    my ($self, %options) = @_;

    my $stat = $options{custom}->get_server_diagnostics(project_id => $options{project}->{id}, server_id => $options{server}->{id});
    if (defined($stat->{memory_details})) {
        my $used = $stat->{memory_details}->{used} * 1024 * 1024;
        my $total = $stat->{memory_details}->{maximum} * 1024 * 1024;
        $self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{memory} = {
            domainName => $options{domain_name},
            serverName => $options{server}->{name},
            projectName => $options{project}->{name},
            used => $used,
            free => $total - $used,
            prct_used => $used * 100 / $total,
            prct_free => 100 - ($used * 100 / $total),
            total => $total
        };
    }
 
    if (defined($stat->{cpu_details})) {
        $self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{cpu} = {};
        foreach my $cpu (@{$stat->{cpu_details}}) {
            $self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{cpu}->{ $cpu->{id} } = {
                domainName => $options{domain_name},
                serverName => $options{server}->{name},
                projectName => $options{project}->{name},
                cpuId => $cpu->{id},
                cpuTime => sprintf('%d', ($cpu->{time} * 0.001)),
                deltaTime => (Time::HiRes::time() * 1000000)
            };
        }
    }

    if (defined($stat->{nic_details})) {
        foreach my $portId (keys %{$self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{ports}}) {
            foreach (@{$stat->{nic_details}}) {
                next if ($self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{ports}->{$portId}->{macAddress} ne $_->{mac_address});

                $self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{ports}->{$portId}->{trafficIn} = $_->{rx_octets} * 8;
                $self->{servers}->{ $options{project}->{id} . $options{server}->{id} }->{ports}->{$portId}->{trafficOut} = $_->{tx_octets} * 8;
            }
        }
    }
}

sub get_network {
    my ($self, %options) = @_;

    foreach (@{$options{networks}}) {
        return $_ if ($_->{id} eq $options{network_id});
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{global} = { detected => 0 };
    $self->{projects} = {};
    $self->{servers} = {};

    my $projects = $options{custom}->get_projects();
    my $domain_name = $options{custom}->get_current_domain_name();
    foreach my $project (@$projects) {
        next if (defined($self->{option_results}->{filter_project_name}) && $self->{option_results}->{filter_project_name} ne '' &&
            $project->{name} !~ /$self->{option_results}->{filter_project_name}/);

        if (!defined($self->{projects}->{ $project->{id} })) {
            $self->{projects}->{ $project->{id} } = {
                projectName => $project->{name},
                noState => 0, running => 0, paused => 0, 
                shutdown => 0, crashed => 0, suspended => 0,
                total => 0
            };
        }

        my $servers = $options{custom}->get_servers(project_id => $project->{id});
        my $networks = $options{custom}->get_networks(project_id => $project->{id});
        my $ports = $options{custom}->get_ports(project_id => $project->{id});

        foreach my $server (@$servers) {
            next if (defined($self->{option_results}->{filter_server_name}) && $self->{option_results}->{filter_server_name} ne '' &&
               $server->{name} !~ /$self->{option_results}->{filter_server_name}/);

            $self->{servers}->{ $project->{id} . $server->{id} } = {
                serverName => $server->{name},
                projectName => $project->{name},
                health => {
                    serverName => $server->{name},
                    projectName => $project->{name},
                    vmState => lc($server->{'OS-EXT-STS:vm_state'}),
                    powerState => $map_power_state->{ $server->{'OS-EXT-STS:power_state'} }
                },
                ports => {}
            };

            foreach my $port (@$ports) {
                next if ($port->{device_owner} !~ /^compute:/ || $port->{device_id} ne $server->{id});

                my $network = $self->get_network(networks => $networks, network_id => $port->{network_id});

                $self->{servers}->{ $project->{id} . $server->{id} }->{ports}->{ $port->{id} } = {
                    domainName => $domain_name,
                    serverName => $server->{name},
                    projectName => $project->{name},
                    macAddress => $port->{mac_address},
                    portId => $port->{id},
                    networkName => $network->{name},
                    portStatus => lc($port->{status}),
                    networkStatus => lc($network->{status})
                };
            }

            if (defined($self->{option_results}->{add_stats})) {
                $self->add_stats(custom => $options{custom}, project => $project, server => $server, domain_name => $domain_name);
            }

            $self->{projects}->{ $project->{id} }->{ $map_power_state->{ $server->{'OS-EXT-STS:power_state'} } }++;
            $self->{projects}->{ $project->{id} }->{total}++;
            $self->{global}->{detected}++;
        }
    }

    $self->{cache_name} = 'openstack_' . $self->{mode} . '_' .
        md5_hex(
            $options{custom}->get_connection_info() . '_' .
            (defined($self->{option_results}->{filter_counters}) ? md5_hex($self->{option_results}->{filter_counters}) : '') . '_' .
            (defined($self->{option_results}->{filter_project_name}) ? md5_hex($self->{option_results}->{filter_project_name}) : '') . '_' .
            (defined($self->{option_results}->{filter_server_name}) ? md5_hex($self->{option_results}->{filter_server_name}) : '')
        );
}

1;

__END__

=head1 MODE

Check servers.

=over 8

=item B<--add-stats>

Add server statistics (need virt driver microversion 2.48).

=item B<--filter-project-name>

Filter servers by project name.

=item B<--filter-server-name>

Filter server by server name.

=item B<--custom-perfdata-instances>

Define perfdatas instance (default: '%(projectName) %(serverName)')

=item B<--unknown-health>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: %{vmState}, %{powerState}, %{serverName}, %{projectName}

=item B<--warning-health>

Define the conditions to match for the status to be WARNING (default: '%{vmState} =~ /rescued/i').
You can use the following variables: %{vmState}, %{powerState}, %{serverName}, %{projectName}

=item B<--critical-health>

Define the conditions to match for the status to be CRITICAL (default: '%{powerState} =~ /crashed/i or %{vmState} =~ /error/i').
You can use the following variables: %{vmState}, %{powerState}, %{serverName}, %{projectName}

=item B<--unknown-port-status>

Define the conditions to match for the status to be UNKNOWN.
You can use the following variables: %{portStatus}, %{networkStatus}, %{serverName}, %{projectName}

=item B<--warning-port-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: %{portStatus}, %{networkStatus}, %{serverName}, %{projectName}

=item B<--critical-port-status>

Define the conditions to match for the status to be CRITICAL (default: '%{networkStatus} =~ /down|error/i or %{portStatus} =~ /down|error/i').
You can use the following variables: %{portStatus}, %{networkStatus}, %{serverName}, %{projectName}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'servers-detected',
'project-servers-power-status-crashed', 'project-servers-power-status-nostate', 'project-servers-power-status-paused',
'project-servers-power-status-running', 'project-servers-power-status-shutdown', 'project-servers-power-status-suspended',
'cpu-utilization',
'memory-usage', 'memory-usage-free', 'memory-usage-prct',
'traffic-in', 'traffic-out'.

=back

=cut
