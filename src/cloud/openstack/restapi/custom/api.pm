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

package cloud::openstack::restapi::custom::api;

use strict;
use warnings;
use centreon::plugins::http;
use centreon::plugins::statefile;
use JSON::XS;
use Digest::MD5 qw(md5_hex);

sub new {
    my ($class, %options) = @_;
    my $self  = {};
    bless $self, $class;

    if (!defined($options{output})) {
        print "Class Custom: Need to specify 'output' argument.\n";
        exit 3;
    }
    if (!defined($options{options})) {
        $options{output}->add_option_msg(short_msg => "Class Custom: Need to specify 'options' argument.");
        $options{output}->option_exit();
    }
    
    if (!defined($options{noptions})) {
        $options{options}->add_options(arguments => {
            'identity-endpoint:s'     => { name => 'identity_endpoint', default => '' },
            'compute-endpoint:s'      => { name => 'compute_endpoint', default => '' },
            'network-endpoint:s'      => { name => 'network_endpoint', default => '' },
            'loadbalancer-endpoint:s' => { name => 'loadbalancer_endpoint', default => '' },
            'api-username:s'         => { name => 'api_username', default => '' },
            'api-password:s'         => { name => 'api_password', default => '' },
            'api-domain:s'           => { name => 'api_domain' },
            'timeout:s'              => { name => 'timeout' },
            'unknown-http-status:s'  => { name => 'unknown_http_status' },
            'warning-http-status:s'  => { name => 'warning_http_status' },
            'critical-http-status:s' => { name => 'critical_http_status' },
            'cache-use'              => { name => 'cache_use' },
            'cache-lifetime:s'       => { name => 'cache_lifetime', default => '' },
            'authent-by-env'         => { name => 'authent_by_env' },
            'authent-by-file:s'      => { name => 'authent_by_file', default => '' }
        });
    }
    $options{options}->add_help(package => __PACKAGE__, sections => 'REST API OPTIONS', once => 1);

    $self->{output} = $options{output};
    $self->{http} = centreon::plugins::http->new(%options, default_backend => 'curl');
    $self->{cache_connect_unscoped} = centreon::plugins::statefile->new(%options);
    $self->{cache_connect_scoped} = centreon::plugins::statefile->new(%options);
    $self->{cache} = centreon::plugins::statefile->new(%options);
    $self->{tokens} = {};
    
    return $self;
}

sub set_options {
    my ($self, %options) = @_;

    $self->{option_results} = $options{option_results};
}

sub set_defaults {}

sub check_options {
    my ($self, %options) = @_;

    $self->{option_results}->{timeout} = (defined($self->{option_results}->{timeout})) ? $self->{option_results}->{timeout} : 50;
    $self->{unknown_http_status} = (defined($self->{option_results}->{unknown_http_status})) ? $self->{option_results}->{unknown_http_status} : '%{http_code} < 200 or %{http_code} >= 300';
    $self->{warning_http_status} = (defined($self->{option_results}->{warning_http_status})) ? $self->{option_results}->{warning_http_status} : '';
    $self->{critical_http_status} = (defined($self->{option_results}->{critical_http_status})) ? $self->{option_results}->{critical_http_status} : '';
    $self->{api_username} = $self->{option_results}->{api_username};
    $self->{api_password} = $self->{option_results}->{api_password};
    $self->{api_domain} = (defined($self->{option_results}->{api_domain}) && $self->{option_results}->{api_domain} ne '') ? $self->{option_results}->{api_domain} : 'default';
    $self->{cache_lifetime} = $self->{option_results}->{cache_lifetime} =~ /(\d+)/ ? $1 : 1800;

    if (defined($self->{option_results}->{authent_by_env})) {
        $self->apply_env_config();
    }
    if (defined($self->{option_results}->{authent_by_file}) && $self->{option_results}->{authent_by_file} ne '') {
        $self->apply_file_config();
    }

    if ($self->{option_results}->{identity_endpoint} eq '') {
        $self->{output}->add_option_msg(short_msg => "Need to specify --identity-endpoint option.");
        $self->{output}->option_exit();
    }
    if ($self->{api_username} eq '') {
        $self->{output}->add_option_msg(short_msg => "Need to specify --api-username option.");
        $self->{output}->option_exit();
    }
    if ($self->{api_password} eq '') {
        $self->{output}->add_option_msg(short_msg => "Need to specify --api-password option.");
        $self->{output}->option_exit();
    }

    $self->{cache_connect_unscoped}->check_options(option_results => $self->{option_results});
    $self->{cache_connect_scoped}->check_options(option_results => $self->{option_results});
    $self->{cache}->check_options(option_results => $self->{option_results});

    return 0;
}

my %_external_conf_equiv = (
    OS_USERNAME => 'api_username',
    OS_PASSWORD => 'api_password',
    OS_PROJECT_DOMAIN_NAME => 'api_domain',
    OS_AUTH_URL => 'identity_endpoint'
);

sub apply_env_config {
    my ($self, %options) = @_;

    # https://docs.openstack.org/python-openstackclient/latest/cli/authentication.html
    foreach (keys %_external_conf_equiv) {
        $self->{ $_external_conf_equiv{$_} } = $ENV{$_}
            if (exists($ENV{$_}));
    }
}

sub apply_file_config {
    my ($self, %options) = @_;

    open(my $file, "<".$options{apply_conf_from_file})
        or $self->{output}->option_exit(short_msg => "Cannot open file '".$options{apply_conf_from_file}."': $!");
    foreach my $line (<$file>) {
        next unless ($line =~ /^[\s\t]*export[\t\s]+(\w+)=["']?(.*?)["']?$/);

        $self->{$_external_conf_equiv{$1}} = $2
            if (exists($_external_conf_equiv{$1}));
    }
    close($file);
}

sub get_connection_info {
    my ($self, %options) = @_;

    return $self->{option_results}->{identity_endpoint} . ':' . $self->{api_domain} . ':' . $self->{option_results}->{api_username};
}

sub settings {
    my ($self, %options) = @_;

    return if (defined($self->{settings_done}));
    $self->{option_results}->{hostname} = '';
    $self->{http}->set_options(%{$self->{option_results}});
    $self->{http}->add_header(key => 'Accept', value => 'application/json');
    $self->{http}->add_header(key => 'Content-Type', value => 'application/json');
    $self->{settings_done} = 1;
}

sub clean_token {
    my ($self, %options) = @_;

    $self->{tokens} = {};
    my $datas = { updated => time() };
    $self->{cache_connect_unscoped}->write(data => $datas);
    $self->{cache_connect_scoped}->write(data => $datas);
}

sub get_current_domain_name {
    my ($self, %options) = @_;

    return $self->{'cache_connect_unscoped'}->get(name => 'domain_name');
}

sub get_endpoint {
    my ($self, %options) = @_;

    return $self->{option_results}->{identity_endpoint} if ($options{type} eq 'identity');

    return $self->{option_results}->{$options{type} . '_endpoint'}  
        if (defined($self->{option_results}->{$options{type} . '_endpoint'}) && 
            $self->{option_results}->{$options{type} . '_endpoint'} ne '');

    my $has_cache_file = $self->{cache_connect_unscoped}->read(statefile => 'openstack_' . md5_hex($self->get_connection_info() . 'unscoped'));
    my $endpoints = $self->{cache_connect_unscoped}->get(name => 'endpoints');

    return $endpoints->{$options{type}}
        if (defined($endpoints->{$options{type}}) && 
            $endpoints->{$options{type}} ne '');

    $self->{output}->add_option_msg(short_msg => "Cannot find endpoint '$options{type}'");
    $self->{output}->option_exit();
}

sub get_token {
    my ($self, %options) = @_;

    # avoid to read the statefile for each calls
    my $token_type = 'unscoped';
    my $project_id = 'none';
    if (defined($options{project_id}) && $options{project_id} ne '') {
        $token_type = 'scoped';
        $project_id = $options{project_id};
    }

    if (defined($self->{tokens}->{$token_type . $project_id})) {
        return $self->{tokens}->{$token_type . $project_id};
    }

    my $has_cache_file = $self->{'cache_connect_' . $token_type}->read(statefile => 'openstack_' . md5_hex($self->get_connection_info() . $token_type));
    my $token = $self->{'cache_connect_' . $token_type}->get(name => 'token');
    my $md5_secret_cache = $self->{'cache_connect_' . $token_type}->get(name => 'md5_secret');
    my $md5_secret = md5_hex($self->{api_username} . $self->{api_password});

    if ($has_cache_file == 0 ||
        !defined($token) ||
        !defined($token->{$project_id}) ||
        (defined($md5_secret_cache) && $md5_secret_cache ne $md5_secret)
        ) {
        my $json_request;
        if (defined($options{project_id})) {
            $json_request = {
                auth => {
                    identity => {
                        methods => ['token'],
                        token => { id => $self->get_token() }
                    },
                    scope => {
                        project => {
                            id => $options{project_id}
                        }
                    }
                }
            };
        } else {
            $json_request = {
                auth => {
                    identity => {
                        methods => ['password'],
                    },
                    password => {
                        user => {
                            name => $self->{api_username},
                            domain => {
                                name => $self->{api_domain}
                            },
                            password => $self->{api_password}
                        }
                    }
                }
            };
        }

        my $encoded;
        eval {
            $encoded = encode_json($json_request);
        };
        if ($@) {
            $self->{output}->add_option_msg(short_msg => 'cannot encode json request');
            $self->{output}->option_exit();
        }

        my $content = $self->{http}->request(
            method => 'POST',
            full_url => $self->{option_results}->{identity_endpoint} . '/v3/auth/tokens',
            query_form_post => $encoded,
            unknown_status => $self->{unknown_http_status},
            warning_status => $self->{warning_http_status},
            critical_status => $self->{critical_http_status},
            header => ['Content-Type: application/json']
        );

        my $ntoken = $self->{http}->get_header(name => 'x-subject-token');

        if (!defined($ntoken)) {
            $self->{output}->add_option_msg(short_msg => "Cannot find token");
            $self->{output}->option_exit();
        }

        my $decoded;
        eval {
            $decoded = JSON::XS->new->decode($content);
        };
        if ($@) {
            $self->{output}->add_option_msg(short_msg => "Cannot decode response (add --debug option to display returned content)");
            $self->{output}->option_exit();
        }

        my $domain_name = '';
        my $endpoints = {
            compute => '',
            loadbalancer => '',
            network => ''
        };
        if (!defined($options{project_id})) {
            $domain_name = $decoded->{token}->{project}->{domain}->{name};
            if (defined($decoded->{token}->{catalog})) {
                foreach my $catalog (@{$decoded->{token}->{catalog}}) {
                    $catalog->{type} =~ s/-//g;

                    next if (!defined($endpoints->{ $catalog->{type} }));

                    foreach (@{$catalog->{endpoints}}) {
                        if ($_->{interface} eq 'public') {
                            $endpoints->{ $catalog->{type} } = $_->{url};
                        }
                    }
                }
            }
        }

        $token = {} if (!defined($token));
        $token->{$project_id} = $ntoken;

        my $datas = {
            updated => time(),
            token => $token,
            md5_secret => $md5_secret,
            endpoints => $endpoints,
            domain_name => $domain_name
        };
        $self->{'cache_connect_' . $token_type}->write(data => $datas);
    }

    $self->{tokens}->{$token_type . $project_id} = $token->{$project_id};

    return $self->{tokens}->{$token_type . $project_id};
}

sub request_api {
    my ($self, %options) = @_;

    $self->settings();
    my $token = $self->get_token(project_id => $options{project_id});

    my $endpoint = $options{endpoint};
    if (defined($options{endpoint_type})) {
        $endpoint = $self->get_endpoint(type => $options{endpoint_type}) . $options{endpoint};
    }

    my ($content) = $self->{http}->request(
        full_url => $endpoint,
        get_param => $options{get_param},
        header => ['X-Auth-Token: ' . $token],
        unknown_status => '',
        warning_status => '',
        critical_status => ''
    );

    # Maybe token is invalid. so we retry
    if ($self->{http}->get_code() < 200 || $self->{http}->get_code() >= 300) {
        $self->clean_token();
        $token = $self->get_token(project_id => $options{project_id});

        $endpoint = $options{endpoint};
        if (defined($options{endpoint_type})) {
            $endpoint = $self->get_endpoint(type => $options{endpoint_type}) . $options{endpoint};
        }

        $content = $self->{http}->request(
            full_url => $endpoint,
            get_param => $options{get_param},
            header => ['X-Auth-Token: ' . $token],
            unknown_status => $self->{unknown_http_status},
            warning_status => $self->{warning_http_status},
            critical_status => $self->{critical_http_status}
        );
    }

    if (!defined($content) || $content eq '') {
        $self->{output}->add_option_msg(short_msg => "API returns empty content [code: '" . $self->{http}->get_code() . "'] [message: '" . $self->{http}->get_message() . "']");
        $self->{output}->option_exit();
    }

    my $decoded;
    eval {
        $decoded = JSON::XS->new->decode($content);
    };
    if ($@) {
        $self->{output}->add_option_msg(short_msg => "Cannot decode response (add --debug option to display returned content)");
        $self->{output}->option_exit();
    }

    return $decoded;
}

sub request {
    my ($self, %options) = @_;

    my $datas = [];
    my $endpoint_type = $options{endpoint_type};
    my $endpoint = $options{endpoint};
    my $get_param = $options{get_param};
    while (defined($endpoint)) {
        my $result = $self->request_api(
            project_id => $options{project_id},
            endpoint_type => $endpoint_type,
            endpoint => $endpoint,
            get_param => $get_param
        );
        $endpoint_type = undef;
        $endpoint = undef;

        # get the raw result (no paging)
        if (!defined($options{data_attr})) {
            return $result;
        }

        if (ref($result->{ $options{data_attr} }) eq 'HASH') {
            $result->{ $options{data_attr} } = [ $result->{ $options{data_attr} } ];
        }

        foreach (@{$result->{ $options{data_attr} }}) {
            my $entry = {};
            foreach my $attr (@{$options{read_attrs}}) {
                next if (!defined($_->{$attr}));
                
                $entry->{$attr} = $_->{$attr};
            }

            push @$datas, $entry;
        }


        if (defined($options{paging_attr}) && defined($result->{ $options{paging_attr} })) {
            foreach (@{$result->{ $options{paging_attr} }}) {
                if ($_->{rel} eq 'next') {
                    $endpoint = $_->{href};
                    $get_param = undef;
                }
            }
        }
    }

    return $datas;
}

sub write_cache_file {
    my ($self, %options) = @_;

    $self->{cache}->read(statefile => 'openstack_' . $options{statefile} . '_' . md5_hex($self->get_connection_info()));
    $self->{cache}->write(data => {
        update_time => time(),
        response => $options{response}
    });
}

sub get_cache_file_response {
    my ($self, %options) = @_;

    $self->{cache}->read(statefile => 'openstack_' . $options{statefile} . '_' . md5_hex($self->get_connection_info()));
    my $response = $self->{cache}->get(name => 'response');
    if (!defined($response)) {
        $self->{output}->add_option_msg(short_msg => 'Cache file missing');
        $self->{output}->option_exit();
    }

    my $update_time = $self->{cache}->get(name => 'update_time');
    if ((time() - $self->{cache_lifetime}) > $update_time) {
        $self->{output}->add_option_msg(short_msg => 'Cache file expired');
        $self->{output}->option_exit();
    }

    return $response;
}

sub cache_servers {
    my ($self, %options) = @_;

    my $datas = $self->get_servers(disable_cache => 1, project_id => $options{project_id});
    $self->write_cache_file(
        statefile => 'servers_' . $options{project_id},
        response => $datas
    );

    return $datas;
}

sub cache_projects {
    my ($self, %options) = @_;

    my $datas = $self->get_projects(disable_cache => 1);
    $self->write_cache_file(
        statefile => 'projects',
        response => $datas
    );

    return $datas;
}

sub cache_loadbalancers {
    my ($self, %options) = @_;

    my $datas = $self->get_loadbalancers(disable_cache => 1, project_id => $options{project_id});
    $self->write_cache_file(
        statefile => 'loadbalancers_' . $options{project_id},
        response => $datas
    );

    return $datas;
}

sub cache_networks {
    my ($self, %options) = @_;

    my $datas = $self->get_networks(disable_cache => 1, project_id => $options{project_id});
    $self->write_cache_file(
        statefile => 'networks_' . $options{project_id},
        response => $datas
    );

    return $datas;
}

sub cache_ports {
    my ($self, %options) = @_;

    my $datas = $self->get_ports(disable_cache => 1, project_id => $options{project_id});
    $self->write_cache_file(
        statefile => 'ports_' . $options{project_id},
        response => $datas
    );

    return $datas;
}

sub get_servers {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'servers_' . $options{project_id})
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'compute',
        endpoint => '/servers/detail',
        data_attr => 'servers',
        paging_attr => 'servers_links',
        read_attrs => ['id', 'name', 'status', 'tenant_id', 'OS-EXT-STS:vm_state', 'OS-EXT-STS:power_state', 'OS-EXT-AZ:availability_zone']
    );

    return $datas;
}

sub get_server_diagnostics {
    my ($self, %options) = @_;

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'compute',
        endpoint => '/servers/' . $options{server_id} . '/diagnostics'
    );

    return $datas;
}

sub get_projects {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'projects')
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        endpoint_type => 'identity',
        endpoint => '/v3/auth/projects',
        data_attr => 'projects',
        paging_attr => 'projects_links',
        read_attrs => ['id', 'name']
    );

    return $datas;
}

sub get_loadbalancers {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'loadbalancers_' . $options{project_id})
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'loadbalancer',
        endpoint => '/v2/lbaas/loadbalancers',
        data_attr => 'loadbalancers',
        paging_attr => 'loadbalancers_links',
        read_attrs => ['id', 'name', 'provisioning_status', 'operating_status']
    );

    return $datas;
}

sub get_loadbalancer_stats {
    my ($self, %options) = @_;

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'loadbalancer',
        endpoint => '/v2/lbaas/loadbalancers/' . $options{lb_id} . '/stats',
        data_attr => 'stats',
        read_attrs => ['bytes_in', 'bytes_out', 'active_connections', 'total_connections', 'request_errors']
    );

    return $datas;
}

sub get_networks {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'networks_' . $options{project_id})
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'network',
        endpoint => '/v2.0/networks',
        data_attr => 'networks',
        paging_attr => 'networks_links',
        read_attrs => ['id', 'name', 'tenant_id', 'status', 'admin_state_up']
    );

    return $datas;
}

sub get_ports {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'ports_' . $options{project_id})
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        project_id => $options{project_id},
        endpoint_type => 'network',
        endpoint => '/v2.0/ports',
        data_attr => 'ports',
        paging_attr => 'ports_links',
        read_attrs => ['id', 'name', 'network_id', 'tenant_id', 'admin_state_up', 'status', 'device_id', 'device_owner', 'mac_address']
    );

    return $datas;
}

1;

__END__

=head1 NAME

OpenStack Rest API

=head1 REST API OPTIONS

OpenStack Rest API

=over 8

=item B<--identity-endpoint>

Set API endpoint for identity service (e.g: https://local.openstack:5000)

=item B<--compute-endpoint>

Set API endpoint for compute service (discovered at authentication. e.g: https://local.openstack:8774/v2.1)

=item B<--network-endpoint>

Set API endpoint for network service (discovered at authentication. e.g: https://local.openstack:9696)

=item B<--loadbalancer-endpoint>

Set API endpoint for load balancer service (discovered at authentication. e.g: https://local.openstack:9876)

=item B<--api-username>

Set username.

=item B<--api-password>

Set password.

=item B<--api-domain>

Set domain (default: 'default').

=item B<--timeout>

Set timeout in seconds (default: 50).

=item B<--cache-use>

Use the cache file (created with cache mode).

=item B<--cache-lifetime>

Define the cache lifetime before raising an error (default: 1800 seconds). 

=item B<--authent-by-env>

Use OpenStack environment variables if they are defined.
Used environment variables are OS_USERNAME, OS_PASSWORD, OS_PROJECT_DOMAIN_NAME, OS_AUTH_URL.

=item B<--authent-by-file>

Read OpenStack environment variables from a file.
Handled environment variables are OS_USERNAME, OS_PASSWORD, OS_PROJECT_DOMAIN_NAME, OS_AUTH_URL.
Those variables must be defined using 'export VARIABLE="value"' syntax.

=back

=head1 DESCRIPTION

B<custom>.

=cut
