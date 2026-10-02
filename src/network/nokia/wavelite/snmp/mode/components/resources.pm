#
# Copyright 2024 Centreon (http://www.centreon.com/)
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

package network::nokia::wavelite::snmp::mode::components::resources;

use strict;
use warnings;
use Exporter;

our %physical_class;
our %phys_status;
our %oids;
our $mapping;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(%physical_class %phys_status %oids $mapping);

%physical_class = (
    1 => 'other',
    2 => 'unknown',
    3 => 'chassis',
    4 => 'backplane',
    5 => 'container', 
    6 => 'powerSupply',
    7 => 'fan',
    8 => 'sensor',
    9 => 'module', 
    10 => 'port',
    11 => 'stack'
);

%phys_status = (
    1 => 'cardRemoved', 
    2 => 'commFault', 
    4 => 'majorAlarm',
    8 => 'HWFailure ',
    16 => 'SWFailure',
    32 => 'SWversionMismatch',
    64 => 'powerAfail',
    128 => 'powerBfail',
    256 => 'HWversionMismatch',
    512 => 'minorAlarm'
);

%oids = (
    entPhysicalDescr     => '.1.3.6.1.4.1.51450.1.3.6.1.1.1.2', # slEntPhysicalDescr
    entPhysicalClass     => '.1.3.6.1.4.1.51450.1.3.6.1.1.1.3', # slEntPhysicalClass
    entPhysicalSerialNum => '.1.3.6.1.4.1.51450.1.3.6.1.1.1.7', # slEntPhysicalSerialNum
    entPhysicalStatus    => '.1.3.6.1.4.1.51450.1.3.6.1.1.1.15' # slEntPhysicalStatus
);

$mapping = {
    entPhysicalDescr     => { oid => $oids{entPhysicalDescr} },
    entPhysicalSerialNum => { oid => $oids{entPhysicalSerialNum} },
    entPhysicalStatus    => { oid => $oids{entPhysicalStatus} }
};

sub get_statuses {
    my (%options) = @_;

    my $statuses = [];
    foreach (keys %phys_status) {
        push @$statuses, $phys_status{$_} if ($options{value} & $_);
    }

    $statuses = ['ok'] if (scalar(@$statuses) == 0);

    return $statuses;
}

1;
