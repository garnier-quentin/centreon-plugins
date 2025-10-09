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
            'identity-endpoint:s'     => { name => 'identity_endpoint' },
            'compute-endpoint:s'      => { name => 'compute_endpoint' },
            'network-endpoint:s'      => { name => 'network_endpoint' },
            'loadbalancer-endpoint:s' => { name => 'loadbalancer_endpoint' },
            'api-username:s'         => { name => 'api_username' },
            'api-password:s'         => { name => 'api_password' },
            'api-domain:s'           => { name => 'api_domain' },
            'timeout:s'              => { name => 'timeout' },
            'unknown-http-status:s'  => { name => 'unknown_http_status' },
            'warning-http-status:s'  => { name => 'warning_http_status' },
            'critical-http-status:s' => { name => 'critical_http_status' },
            'cache-use'              => { name => 'cache_use' }
        });
    }
    $options{options}->add_help(package => __PACKAGE__, sections => 'REST API OPTIONS', once => 1);

    $self->{output} = $options{output};
    $self->{http} = centreon::plugins::http->new(%options, default_backend => 'curl');
    $self->{cache_connect} = centreon::plugins::statefile->new(%options);
    $self->{cache} = centreon::plugins::statefile->new(%options);
    
    return $self;
}

sub set_options {
    my ($self, %options) = @_;

    $self->{option_results} = $options{option_results};
}

sub set_defaults {}

sub check_options {
    my ($self, %options) = @_;

    $self->{option_results}->{identity_endpoint} = (defined($self->{option_results}->{identity_endpoint})) ? $self->{option_results}->{identity_endpoint} : '';
    $self->{option_results}->{compute_endpoint} = (defined($self->{option_results}->{compute_endpoint})) ? $self->{option_results}->{compute_endpoint} : '';
    $self->{option_results}->{network_endpoint} = (defined($self->{option_results}->{network_endpoint})) ? $self->{option_results}->{network_endpoint} : '';
    $self->{option_results}->{loadbalancer_endpoint} = (defined($self->{option_results}->{loadbalancer_endpoint})) ? $self->{option_results}->{loadbalancer_endpoint} : '';
    $self->{option_results}->{timeout} = (defined($self->{option_results}->{timeout})) ? $self->{option_results}->{timeout} : 50;
    $self->{unknown_http_status} = (defined($self->{option_results}->{unknown_http_status})) ? $self->{option_results}->{unknown_http_status} : '%{http_code} < 200 or %{http_code} >= 300';
    $self->{warning_http_status} = (defined($self->{option_results}->{warning_http_status})) ? $self->{option_results}->{warning_http_status} : '';
    $self->{critical_http_status} = (defined($self->{option_results}->{critical_http_status})) ? $self->{option_results}->{critical_http_status} : '';
    $self->{api_username} = (defined($self->{option_results}->{api_username})) ? $self->{option_results}->{api_username} : '';
    $self->{api_password} = (defined($self->{option_results}->{api_password})) ? $self->{option_results}->{api_password} : '';
    $self->{api_domain} = (defined($self->{option_results}->{api_domain})) ? $self->{option_results}->{api_domain} : 'default';

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

    $self->{cache_connect}->check_options(option_results => $self->{option_results});
    $self->{cache}->check_options(option_results => $self->{option_results});

    return 0;
}

sub get_connection_info {
    my ($self, %options) = @_;

    return $self->{option_results}->{identity_endpoint} . ':' . $self->{option_results}->{api_username};
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

    my $datas = { updated => time() };
    $self->{cache_connect}->write(data => $datas);
}

sub get_endpoint {
    my ($self, %options) = @_;

    return $self->{option_results}->{identity_endpoint} if ($options{type} eq 'identity');

    return $self->{option_results}->{$options{type} . '_endpoint'}  
        if (defined($self->{option_results}->{$options{type} . '_endpoint'}) && 
            $self->{option_results}->{$options{type} . '_endpoint'} ne '');

    my $has_cache_file = $self->{cache_connect}->read(statefile => 'openstack_' . md5_hex($self->get_connection_info()));
    my $endpoints = $self->{cache_connect}->get(name => 'endpoints');

    return $endpoints->{$options{type}}
        if (defined($endpoints->{$options{type}}) && 
            $endpoints->{$options{type}} ne '');

    $self->{output}->add_option_msg(short_msg => "Cannot find endpoint '$options{type}'");
    $self->{output}->option_exit();
}

sub get_token {
    my ($self, %options) = @_;

    my $has_cache_file = $self->{cache_connect}->read(statefile => 'openstack_' . md5_hex($self->get_connection_info()));
    my $token = $self->{cache_connect}->get(name => 'token');
    my $md5_secret_cache = $self->{cache_connect}->get(name => 'md5_secret');
    my $md5_secret = md5_hex($self->{api_username} . $self->{api_password});

    if ($has_cache_file == 0 ||
        !defined($token) ||
        (defined($md5_secret_cache) && $md5_secret_cache ne $md5_secret)
        ) {
        my $json_request = {
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

        $token = $self->{http}->get_header(name => 'x-subject-token');

        if (!defined($token)) {
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

        my $endpoints = {
            compute => '',
            loadbalancer => '',
            network => ''
        };
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

        my $datas = {
            updated => time(),
            token => $token,
            md5_secret => $md5_secret,
            endpoints => $endpoints
        };
        $self->{cache_connect}->write(data => $datas);
    }

    return $token;
}

sub request_api {
    my ($self, %options) = @_;

    $self->settings();
    my $token = $self->get_token();

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
        $token = $self->get_token();

        $endpoint = $options{endpoint};
        if (defined($options{endpoint_type})) {
            $endpoint = $self->get_endpoint(type => 'compute') . $options{endpoint};
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
            endpoint_type => $endpoint_type,
            endpoint => $endpoint,
            get_param => $get_param
        );
        $endpoint_type = undef;
        $endpoint = undef;

        foreach (@{$result->{ $options{data_attr} }}) {
            my $entry = {};
            foreach my $attr (@{$options{read_attrs}}) {
                next if (!defined($_->{$attr}));
                
                $entry->{$attr} = $_->{$attr};
            }

            push @$datas, $entry;
        }


        if (defined($result->{ $options{paging_attr} })) {
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

    $self->{cache}->read(statefile => 'cache_openstack_' . $options{statefile} . '_' . md5_hex($self->get_connection_info()));
    $self->{cache}->write(data => {
        update_time => time(),
        response => $options{response}
    });
}

sub get_cache_file_response {
    my ($self, %options) = @_;

    $self->{cache}->read(statefile => 'cache_openstack_' . $options{statefile} . '_' . md5_hex($self->get_connection_info()));
    my $response = $self->{cache}->get(name => 'response');
    if (!defined($response)) {
        $self->{output}->add_option_msg(short_msg => 'Cache file missing');
        $self->{output}->option_exit();
    }
    return $response;
}

sub cache_servers {
    my ($self, %options) = @_;

    my $datas = $self->get_servers(disable_cache => 1);
    $self->write_cache_file(
        statefile => 'servers',
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

    my $datas = $self->get_loadbalancers(disable_cache => 1);
    $self->write_cache_file(
        statefile => 'loadbalancers',
        response => $datas
    );

    return $datas;
}

sub get_servers {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'servers')
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        endpoint_type => 'compute',
        endpoint => '/servers/detail',
        data_attr => 'servers',
        paging_attr => 'servers_links',
        read_attrs => ['id', 'name', 'status', 'tenant_id', 'OS-EXT-STS:vm_state', 'OS-EXT-STS:power_state', 'OS-EXT-AZ:availability_zone']
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

    return $self->get_cache_file_response(statefile => 'loadbalancers')
        if (defined($self->{option_results}->{cache_use}) && !defined($options{disable_cache}));

    my $datas = $self->request(
        endpoint_type => 'loadbalancer',
        endpoint => '/v2/lbaas/loadbalancers',
        data_attr => 'loadbalancers',
        paging_attr => 'loadbalancers_links',
        read_attrs => ['id', 'name']
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

=back

=head1 DESCRIPTION

B<custom>.

=cut
