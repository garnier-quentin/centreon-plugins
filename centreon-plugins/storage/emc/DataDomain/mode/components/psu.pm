################################################################################
# Copyright 2005-2013 MERETHIS
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
# 
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation ; either version 2 of the License.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with 
# this program; if not, see <http://www.gnu.org/licenses>.
# 
# Linking this program statically or dynamically with other modules is making a 
# combined work based on this program. Thus, the terms and conditions of the GNU 
# General Public License cover the whole combination.
# 
# As a special exception, the copyright holders of this program give MERETHIS 
# permission to link this program with independent modules to produce an executable, 
# regardless of the license terms of these independent modules, and to copy and 
# distribute the resulting executable under terms of MERETHIS choice, provided that 
# MERETHIS also meet, for each linked independent module, the terms  and conditions 
# of the license of that module. An independent module is a module which is not 
# derived from this program. If you modify this program, you may extend this 
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
# 
# For more information : contact@centreon.com
# Authors : Quentin Garnier <qgarnier@merethis.com>
#
####################################################################################

package storage::emc::DataDomain::mode::components::psu;

use strict;
use warnings;

my %conditions = (
    1 => ['ok', 'OK'],
    2 => ['unknown', 'UNKNOWN'], 
    3 => ['fail', 'CRITICAL'], 
);

sub check {
    my ($self) = @_;

    $self->{components}->{psus} = {name => 'power supplies', total => 0};
    $self->{output}->output_add(long_msg => "Checking power supplies");
    return if ($self->check_exclude('psu'));
    
    my $oid_powerModuleEntry = '.1.3.6.1.4.1.19746.1.1.1.1.1.1';
    my $oid_powerModuleStatus = '.1.3.6.1.4.1.19746.1.1.1.1.1.1.3';
    
    my $result = $self->{snmp}->get_table(oid => $oid_powerModuleEntry);
    return if (scalar(keys %$result) <= 0);

    foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
        next if ($key !~ /^$oid_powerModuleStatus\.(\d+)\.(\d+)$/);
        my ($enclosure_id, $module_index) = ($1, $2);
    
        my $psu_status = $result->{$oid_powerModuleStatus . '.' . $enclosure_id . '.' . $module_index};

        $self->{components}->{psus}->{total}++;
        $self->{output}->output_add(long_msg => sprintf("Power Supply '%s' status is %s.", 
                                                        $enclosure_id . '/' . $module_index, ${$conditions{$psu_status}}[0]));
        if (!$self->{output}->is_status(litteral => 1, value => ${$conditions{$psu_status}}[1], compare => 'ok')) {
            $self->{output}->output_add(severity => ${$conditions{$psu_status}}[1],
                                        short_msg => sprintf("Power Supply '%s' status is %s", $enclosure_id . '/' . $module_index, ${$conditions{$psu_status}}[0]));
        }
    }
}

1;