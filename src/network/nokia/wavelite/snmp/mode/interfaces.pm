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

package network::nokia::wavelite::snmp::mode::interfaces;

use base qw(snmp_standard::mode::interfaces);

use strict;
use warnings;
use centreon::plugins::misc qw(is_empty);

sub set_oids_label {
    my ($self, %options) = @_;

    $self->{oids_label} //= {
        'ifalias' => { oid => '.1.3.6.1.2.1.31.1.1.1.18', get => 'reload_get_simple', cache => 'reload_cache_index_value' },
        'ifname'  => { oid => '.1.3.6.1.2.1.31.1.1.1.1', get => 'reload_get_simple', cache => 'reload_cache_index_value' }
    };
}

sub set_counters_errors {
    my ($self, %options) = @_;
    
    push @{$self->{maps_counters}->{int}}, 
        { label => 'in-crc', filter => 'add_errors', nlabel => 'interface.packets.in.crc.count', set => {
                key_values => [ { name => 'incrc', diff => 1 }, { name => 'total_in_packets', diff => 1 }, { name => 'display' }, { name => 'mode_cast' } ],
                closure_custom_calc => $self->can('custom_errors_calc'), closure_custom_calc_extra_options => { label_ref1 => 'in', label_ref2 => 'crc' },
                closure_custom_output => $self->can('custom_errors_output'), output_error_template => 'Packets In Crc : %s',
                closure_custom_perfdata => $self->can('custom_errors_perfdata'),
                closure_custom_threshold_check => $self->can('custom_errors_threshold')
            }
        },
        { label => 'out-crc', filter => 'add_errors', nlabel => 'interface.packets.out.crc.count', set => {
                key_values => [ { name => 'outcrc', diff => 1 }, { name => 'total_out_packets', diff => 1 }, { name => 'display' }, { name => 'mode_cast' } ],
                closure_custom_calc => $self->can('custom_errors_calc'), closure_custom_calc_extra_options => { label_ref1 => 'out', label_ref2 => 'crc' },
                closure_custom_output => $self->can('custom_errors_output'), output_error_template => 'Packets Out Crc : %s',
                closure_custom_perfdata => $self->can('custom_errors_perfdata'),
                closure_custom_threshold_check => $self->can('custom_errors_threshold')
            }
        }
    ;

    push @{$self->{maps_counters}->{int}},
        { label => 'laser-temp', filter => 'add_optical', nlabel => 'interface.laser.temperature.celsius', set => {
                key_values => [ { name => 'laser_temp' }, { name => 'display' } ],
                output_template => 'Laser temperature: %.2f C', output_error_template => 'Laser temperature: %.2f',
                perfdatas => [
                    { template => '%.2f', unit => 'C', label_extra_instance => 1, instance_use => 'display' }
                ]
            }
        },
        { label => 'input-power', filter => 'add_optical', nlabel => 'interface.input.power.dbm', set => {
                key_values => [ { name => 'input_power' }, { name => 'display' } ],
                output_template => 'Input power: %s dBm', output_error_template => 'Input power: %s',
                perfdatas => [
                    { template => '%s', unit => 'dBm', label_extra_instance => 1, instance_use => 'display' }
                ]
            }
        },
        { label => 'output-power', filter => 'add_optical', nlabel => 'interface.output.power.dbm', set => {
                key_values => [ { name => 'output_power' }, { name => 'display' } ],
                output_template => 'Output power: %s dBm', output_error_template => 'Output power: %s',
                perfdatas => [
                    { template => '%s', unit => 'dBm', label_extra_instance => 1, instance_use => 'display' }
                ]
            }
        }
    ;
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1, no_cast => 1);
    bless $self, $class;

    $options{options}->add_options(arguments => {
        'add-optical' => { name => 'add_optical' }
    });

    return $self;
}

sub reload_cache_custom {
    my ($self, %options) = @_;

    my $oid_ifdesc = '.1.3.6.1.2.1.2.2.1.2';
    my $oid_iftype = '.1.3.6.1.2.1.2.2.1.3';

    my $ifDesc = {};
    my $snmp_result = $self->{snmp}->get_table(oid => $oid_ifdesc);
    foreach (keys %$snmp_result) {
        next if (! /^$oid_ifdesc\.(.*)$/);
        $ifDesc->{$1} = $snmp_result->{$_};
    }

    my $ifType = {};
    $snmp_result = $self->{snmp}->get_table(oid => $oid_iftype);
    foreach (keys %$snmp_result) {
        next if (! /^$oid_iftype\.(.*)$/);
        $ifType->{$1} = $snmp_result->{$_};
    }

    # On opticalTransport interface (196), the speed/traffic is on ethernetCslacd type (6).
    # The traffic is present if the opticalTransport is UP and it's named "SFP Interface XXX"
    # For the mapping we check the ifDesc:
    #   SFP Interface 12 = Line Interface 12
    $options{datas}->{mapOpticalIndex} = {};
    $options{datas}->{isOptical} = {};
    my @indexes = keys %$ifDesc;
    foreach my $ifIndex (@indexes) {
        if ($ifType->{$ifIndex} == 196) {
            $options{datas}->{isOptical}->{$ifIndex} = 1;
        }

        next if ($ifDesc->{$ifIndex} !~ /^SFP\s+Interface\s+(\d+)/i);
        my $num = $1;
        foreach (@indexes) {
            #next if ($ifType->{$_} != 6); seems buggy because we have 195 on some Line Interface

            if ($ifDesc->{$_} =~ /^Line\s+Interface\s+$num/i) {
                $options{datas}->{mapOpticalIndex}->{$ifIndex} = $_; 
                last;
            }
        }
    }
}

my $oid_counter_nokia = '.1.3.6.1.4.1.51450.1.3.25.2.1.1.4';

sub load_status {
    my ($self, %options) = @_;

    $self->set_oids_status();
    my $oids = [ $self->{oid_adminstatus}, $self->{oid_opstatus} ];

    my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');
    foreach (@{$self->{array_interface_selected}}) {
        if (defined($opticalIndexes->{$_})) {
            $self->{snmp}->load(oids => $oids, instances => [$opticalIndexes->{$_}]);
        } else {
            $self->{snmp}->load(oids => $oids, instances => [$_]);
        }
    }
}

sub load_traffic {
    my ($self, %options) = @_;

    $self->set_oids_traffic();

    return if ($self->{snmp}->is_snmpv1());

    my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');

    foreach (@{$self->{array_interface_selected}}) {
        next if (!defined($opticalIndexes->{$_}));

        $self->{snmp}->load(oids => [
                $self->{oid_speed32} . '.' . $_,
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.3.2.0', # oid_in64
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.4.2.0', # oid_out64
            ]
        );
    }
}

sub load_errors {
    my ($self, %options) = @_;

    return if ($self->{snmp}->is_snmpv1());

    my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');

    foreach (@{$self->{array_interface_selected}}) {
        next if (!defined($opticalIndexes->{$_}));

        $self->{snmp}->load(oids => [
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.1.2.0', # oid_packets_in
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.2.2.0', # oid_packets_out
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.5.2.0', # oid_in_crc
                $oid_counter_nokia . '.' . $opticalIndexes->{$_} . '.6.2.0', # oid_out_crc
            ]
        );
    }
}

my $oid_optical_laser_temp = '.1.3.6.1.4.1.51450.1.10.2.1.1.57'; # sfpDiagModuleTemperatureCelsius
my $oid_optical_input_power = '.1.3.6.1.4.1.51450.1.10.2.1.1.61'; # sfpDiagRxInputPowerDbm
my $oid_optical_output_power = '.1.3.6.1.4.1.51450.1.10.2.1.1.60'; # sfpDiagTxOutputPowerDbm

sub custom_load {
    my ($self, %options) = @_;

    return if (!defined($self->{option_results}->{add_optical}));

    my $isOptical = $self->{statefile_cache}->get(name => 'isOptical');

    foreach (@{$self->{array_interface_selected}}) {
        next if (!defined($isOptical->{$_}));

        $self->{snmp}->load(oids => [
                $oid_optical_laser_temp . '.' . $_,
                $oid_optical_input_power . '.' . $_,
                $oid_optical_output_power . '.' . $_
            ]
        );
    }
}

sub add_result_traffic {
    my ($self, %options) = @_;

    $self->{int}->{$options{instance}}->{mode_traffic} = 32;
    if (!$self->{snmp}->is_snmpv1()) {
        $self->{int}->{$options{instance}}->{mode_traffic} = 64;
        my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');
        if (defined($opticalIndexes->{ $options{instance} })) {
            $self->{int}->{$options{instance}}->{in} = $self->{results}->{ $oid_counter_nokia . '.' . $opticalIndexes->{ $options{instance} } . '.3.2.0' };
            $self->{int}->{$options{instance}}->{out} = $self->{results}->{ $oid_counter_nokia . '.' . $opticalIndexes->{ $options{instance} } . '.4.2.0' };
        }
    }

    $self->{int}->{$options{instance}}->{in} *= 8 if (defined($self->{int}->{$options{instance}}->{in}));
    $self->{int}->{$options{instance}}->{out} *= 8 if (defined($self->{int}->{$options{instance}}->{out}));

    $self->{int}->{$options{instance}}->{speed_in} = 0;
    $self->{int}->{$options{instance}}->{speed_out} = 0;
    if ($self->{get_speed} == 0) {
        if (!is_empty($self->{option_results}->{speed})) {
            $self->{int}->{$options{instance}}->{speed_in} = $self->{option_results}->{speed} * 1000000;
            $self->{int}->{$options{instance}}->{speed_out} = $self->{option_results}->{speed} * 1000000;
        }
        $self->{int}->{$options{instance}}->{speed_in} = $self->{option_results}->{speed_in} * 1000000 if (!is_empty($self->{option_results}->{speed_in}));
        $self->{int}->{$options{instance}}->{speed_out} = $self->{option_results}->{speed_out} * 1000000 if (!is_empty($self->{option_results}->{speed_out}));
    } else {
        my $interface_speed = 0;
        if (!is_empty($self->{results}->{$self->{oid_speed64} . '.' . $options{instance}})) {
            $interface_speed = $self->{results}->{$self->{oid_speed64} . '.' . $options{instance}} * 1000000;
            # If 0, we put the 32 bits
            if ($interface_speed == 0 && !defined($self->{option_results}->{force_counters64})) {
                $interface_speed = $self->{results}->{$self->{oid_speed32} . '.' . $options{instance}};
            }
        } else {
            $interface_speed = $self->{results}->{$self->{oid_speed32} . '.' . $options{instance}};
        }

        $self->{int}->{$options{instance}}->{speed_in} = $interface_speed;
        $self->{int}->{$options{instance}}->{speed_out} = $interface_speed;

        $self->{int}->{$options{instance}}->{speed_in} = $self->{option_results}->{speed_in} * 1000000 if (!is_empty($self->{option_results}->{speed_in}));
        $self->{int}->{$options{instance}}->{speed_out} = $self->{option_results}->{speed_out} * 1000000 if (!is_empty($self->{option_results}->{speed_out}));
    }
}

sub add_result_errors {
    my ($self, %options) = @_;

    return if ($self->{snmp}->is_snmpv1());
 
    my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');
    return if (!defined($opticalIndexes->{ $options{instance} }));
 
    $self->{int}->{$options{instance}}->{total_in_packets} = $self->{results}->{ $oid_counter_nokia . '.' . $opticalIndexes->{ $options{instance} } . '.1.2.0' };
    $self->{int}->{$options{instance}}->{total_out_packets} = $self->{results}->{ $oid_counter_nokia . '.' . $opticalIndexes->{ $options{instance} } . '.2.2.0' };
    $self->{int}->{$options{instance}}->{incrc} = $self->{results}->{ $oid_counter_nokia . '.' . $options{instance} . '.5.2.0' };
    $self->{int}->{$options{instance}}->{outcrc} = $self->{results}->{ $oid_counter_nokia . '.' . $options{instance} . '.6.2.0' };
}

sub add_result_status {
    my ($self, %options) = @_;

    my $opticalIndexes = $self->{statefile_cache}->get(name => 'mapOpticalIndex');
    my $instance = $options{instance};
    if (defined($opticalIndexes->{$instance})) {
        $instance = $opticalIndexes->{$instance};
    }

    $self->{int}->{$options{instance}}->{opstatus} = defined($self->{results}->{$self->{oid_opstatus} . '.' . $instance}) ? $self->{oid_opstatus_mapping}->{$self->{results}->{$self->{oid_opstatus} . '.' . $instance}} : undef;
    $self->{int}->{$options{instance}}->{admstatus} = defined($self->{results}->{$self->{oid_adminstatus} . '.' . $instance}) ? $self->{oid_adminstatus_mapping}->{$self->{results}->{$self->{oid_adminstatus} . '.' . $instance}} : undef;
    $self->{int}->{$options{instance}}->{duplexstatus} = 'n/a';
}

sub custom_add_result {
    my ($self, %options) = @_;

    return if (!defined($self->{option_results}->{add_optical}));

    my $isOptical = $self->{statefile_cache}->get(name => 'isOptical');
    return if (!defined($isOptical->{ $options{instance} }));

    $self->{int}->{ $options{instance} }->{laser_temp} = $1;

    if (defined($self->{results}->{ $oid_optical_laser_temp . '.' . $options{instance} }) &&
        $self->{results}->{$oid_optical_laser_temp . '.' . $options{instance}} =~ /(\d+)/) {
        $self->{int}->{ $options{instance} }->{laser_temp} = $1;
    }

    # unit 0.1 dBm
    if (defined($self->{results}->{$oid_optical_input_power . '.' . $options{instance}}) &&
        $self->{results}->{$oid_optical_input_power . '.' . $options{instance}} =~ /(-?\d+(?:\.?\d+)?)/) {
        $self->{int}->{ $options{instance} }->{input_power} = $1 * 10;
    }

    # unit 0.1 dBm
    if (defined($self->{results}->{$oid_optical_output_power . '.' . $options{instance}}) &&
        $self->{results}->{$oid_optical_output_power . '.' . $options{instance}} =~ /(-?\d+(?:\.?\d+)?)/) {
        $self->{int}->{ $options{instance} }->{output_power} = $1 * 10;
    }
}

1;

__END__

=head1 MODE

Check interfaces.

=over 8

=item B<--add-global>

Check global port statistics (by default if no --add-* option is set).

=item B<--add-status>

Check interface status.

=item B<--add-traffic>

Check interface traffic.

=item B<--add-errors>

Check interface errors.

=item B<--add-speed>

Check interface speed.

=item B<--add-volume>

Check interface data volume between two checks (not supposed to be graphed, useful for BI reporting).

=item B<--add-optical>

Check interface optical.

=item B<--check-metrics>

If the expression is true, metrics are checked (default: '%{opstatus} eq "up"').

=item B<--warning-status>

Define the conditions to match for the status to be WARNING.
You can use the following variables: %{admstatus}, %{opstatus}, %{duplexstatus}, %{display}

=item B<--critical-status>

Define the conditions to match for the status to be CRITICAL (default: '%{admstatus} eq "up" and %{opstatus} ne "up"').
You can use the following variables: %{admstatus}, %{opstatus}, %{duplexstatus}, %{display}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'total-port', 'total-admin-up', 'total-admin-down', 'total-oper-up', 'total-oper-down',
'in-traffic', 'out-traffic', 'in-crc', 'speed' (b/s), 'laser-temp', 'input-power', 'output-power'.

=item B<--units-traffic>

Units of thresholds for the traffic (default: 'percent_delta') ('percent_delta', 'bps', 'counter').

=item B<--units-errors>

Units of thresholds for errors/discards (default: 'percent_delta') ('percent_delta', 'percent', 'delta', 'deltaps', 'counter').

=item B<--nagvis-perfdata>

Display traffic perfdata to be compatible with nagvis widget.

=item B<--interface>

Set the interface (number expected) example: 1,2,... (empty means 'check all interfaces').

=item B<--name>

Allows you to define the interface (in option --interface) by name instead of OID index. The name matching mode supports regular expressions.

=item B<--speed>

Set interface speed for incoming/outgoing traffic (in Mb).

=item B<--speed-in>

Set interface speed for incoming traffic (in Mb).

=item B<--speed-out>

Set interface speed for outgoing traffic (in Mb).

=item B<--reload-cache-time>

Time in minutes before reloading cache file (default: 180).

=item B<--oid-filter>

Define the OID to be used to filter interfaces (default: ifName) (values: ifAlias, ifName).

=item B<--oid-display>

Define the OID that will be used to name the interfaces (default: ifName) (values: ifAlias, ifName).

=item B<--oid-extra-display>

Add an OID to display.

=item B<--display-transform-src> B<--display-transform-dst>

Modify the interface name displayed by using a regular expression.

Example: adding --display-transform-src='eth' --display-transform-dst='ens'  will replace all occurrences of 'eth' with 'ens'

=item B<--show-cache>

Display cache interface data.

=back

=cut
