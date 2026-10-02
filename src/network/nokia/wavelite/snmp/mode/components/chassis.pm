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

package network::nokia::wavelite::snmp::mode::components::chassis;

use strict;
use warnings;
use network::nokia::wavelite::snmp::mode::components::resources qw(%oids $mapping);

sub load {}

sub check {
    my ($self) = @_;

    $self->{output}->output_add(long_msg => "checking chassis");
    $self->{components}->{chassis} = { name => 'chassis', total => 0, skip => 0 };
    return if ($self->check_filter(section => 'chassis'));
    
    my @instances = ();
    foreach my $key (keys %{$self->{results}->{ $oids{entPhysicalClass} }}) {
        if ($self->{results}->{ $oids{entPhysicalClass} }->{$key} == 3) {
            next if ($key !~ /^$oids{entPhysicalClass}\.(.*)$/);
            push @instances, $1;
        }
    }
    
    foreach my $instance (@instances) {
        my $result = $self->{snmp}->map_instance(mapping => $mapping, results => $self->{results}->{entity}, instance => $instance);

        my $name = $result->{entPhysicalDescr};
        if (defined($result->{entPhysicalSerialNum}) && $result->{entPhysicalSerialNum} ne '') {
            $name .= '/' . $result->{entPhysicalSerialNum};
        }

        next if ($self->check_filter(section => 'chassis', instance => $instance, name => $name));
        $self->{components}->{chassis}->{total}++;

        my $statuses = network::nokia::wavelite::snmp::mode::components::resources::get_statuses(value => $result->{entPhysicalStatus});

        $self->{output}->output_add(
            long_msg => sprintf(
                "chassis '%s' status is %s [instance: %s]",
                $name,
                join('|', @$statuses),
                $instance
            )
        );
 
        foreach my $status (@$statuses) {
            my $exit = $self->get_severity(label => 'default', section => 'chassis', instance => $instance, name => $name, value => $status);
            if (!$self->{output}->is_status(value => $exit, compare => 'ok', litteral => 1)) {
                $self->{output}->output_add(
                    severity => $exit,
                    short_msg => sprintf(
                        "chassis '%s' status is %s",
                        $name,
                        $status
                    )
                );
            }
        }
    }
}

1;
