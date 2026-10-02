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

package network::nokia::wavelite::snmp::mode::listinterfaces;

use base qw(snmp_standard::mode::listinterfaces);

use strict;
use warnings;

sub set_oids_label {
    my ($self, %options) = @_;

    $self->{oids_label} //= {
        'ifalias' => '.1.3.6.1.2.1.31.1.1.1.18',
        'ifname' => '.1.3.6.1.2.1.31.1.1.1.1'
    };
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;    
    return $self;
}

sub get_additional_information {
    my ($self, %options) = @_;

    my $result = $self->SUPER::get_additional_information(%options);

    my $ifDesc = {};
    my $oid_ifdesc = '.1.3.6.1.2.1.2.2.1.2';
    my $snmp_result = $self->{snmp}->get_table(oid => $oid_ifdesc);
    foreach (keys %$snmp_result) {
        next if (! /^$oid_ifdesc\.(.*)$/);
        $ifDesc->{$1} = $snmp_result->{$_};
    }

    my @indexes = keys %$ifDesc;
    my $instances = [];
    my $mapping = {};
    foreach my $ifIndex (@indexes) {
        next if ($ifDesc->{$ifIndex} !~ /^SFP\s+Interface\s+(\d+)/i);
        my $num = $1;
        foreach (@indexes) {
            #next if ($ifType->{$_} != 6); seems buggy because we have 195 on some Line Interface

            if ($ifDesc->{$_} =~ /^Line\s+Interface\s+$num/i) {
                $mapping->{$_} = $ifIndex;
                push @$instances, $_;
                last;
            }
        }
    }

    $snmp_result = undef;
    if (scalar(@$instances) > 0) {
        $self->{snmp}->load(oids => [$self->{oid_adminstatus}, $self->{oid_opstatus}], instances => $instances);
        $snmp_result = $self->{snmp}->get_leef();        
    }

    if (defined($snmp_result)) {
        foreach my $oid (keys %$snmp_result) {
            next if ($oid !~ /^$self->{oid_adminstatus}\.(.*)/i);
            my $ifIndex = $1;

            $result->{ $self->{oid_adminstatus} . '.' . $mapping->{$ifIndex} } = $snmp_result->{$oid};
            $result->{ $self->{oid_opstatus} . '.' . $mapping->{$ifIndex} } = $snmp_result->{ $self->{oid_opstatus} . '.' . $ifIndex };
        }
    }

    return $result;
}

1;

__END__

=head1 MODE

=over 8

=item B<--interface>

Set the interface (number expected) example: 1,2,... (empty means 'check all interfaces').

=item B<--name>

Allows you to define the interface (in option --interface) by name instead of OID index. The name matching mode supports regular expressions.

=item B<--speed>

Set interface speed (in Mb).

=item B<--skip-speed0>

Don't display interface with speed 0.

=item B<--filter-status>

Display interfaces matching the filter (example: 'up').

=item B<--use-adminstatus>

Display interfaces with AdminStatus 'up'.

=item B<--oid-filter>

Define the OID to be used to filter interfaces (default: ifName) (values: ifAlias, ifName).

=item B<--oid-display>

Define the OID that will be used to name the interfaces (default: ifName) (values: ifAlias, ifName).

=item B<--display-transform-src> B<--display-transform-dst>

Modify the interface name displayed by using a regular expression.

Example: adding --display-transform-src='eth' --display-transform-dst='ens'  will replace all occurrences of 'eth' with 'ens'

=item B<--add-extra-oid>

Display an OID.
Example: --add-extra-oid='alias,.1.3.6.1.2.1.31.1.1.1.18'
or --add-extra-oid='vlan,.1.3.6.1.2.1.31.19,%{instance}\..*'

=item B<--add-mac-address>

Display interface mac address.

=back

=cut
