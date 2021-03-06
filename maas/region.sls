{%- from "maas/map.jinja" import region with context %}
{%- if region.get('enabled', False) %}

maas_region_packages:
  pkg.installed:
    - names: {{ region.pkgs }}

/etc/maas/regiond.conf:
  file.managed:
  - source: salt://maas/files/regiond.conf
  - template: jinja
  - group: maas
  - require:
    - pkg: maas_region_packages

/usr/lib/python3/dist-packages/provisioningserver/templates/proxy/maas-proxy.conf.template:
  file.managed:
  - source: salt://maas/files/maas-proxy.conf.template
  - template: jinja
  - require:
    - pkg: maas_region_packages

{%- if region.database.initial_data is defined %}

/root/maas/scripts/restore_{{ region.database.name }}.sh:
  file.managed:
    - source: salt://maas/files/restore.sh
    - mode: 770
    - makedirs: true
    - template: jinja

restore_maas_database_{{ region.database.name }}:
  cmd.run:
  - name: /root/maas/scripts/restore_{{ region.database.name }}.sh
  - unless: "[ -f /root/maas/flags/{{ region.database.name }}-installed ]"
  - cwd: /root
  - require:
    - file: /root/maas/scripts/restore_{{ region.database.name }}.sh

{%- endif %}

{%- if region.get('enable_iframe', False)  %}

/etc/apache2/conf-enabled/maas-http.conf:
  file.managed:
  - source: salt://maas/files/maas-http.conf
  - user: root
  - group: root
  - mode: 644
  - require:
    - pkg: maas_region_packages
  - require_in:
    - service: maas_region_services

maas_apache_headers:
  cmd.run:
  - name: "a2enmod headers"
  - require:
    - pkg: maas_region_packages
  - require_in:
    - service: maas_region_services

{%- endif %}

{% if region.theme is defined %}

/usr/share/maas/web/static/css/maas-styles.css:
  file.managed:
  - source: salt://maas/files/{{ region.theme }}-styles.css
  - mode: 644
  - watch_in:
    - service: maas_region_services

{%- endif %}

/etc/maas/preseeds/curtin_userdata_amd64_generic_trusty:
  file.managed:
  - source: salt://maas/files/curtin_userdata_amd64_generic_trusty
  - template: jinja
  - user: root
  - group: root
  - mode: 644
  - context:
      salt_master_ip: {{ region.salt_master_ip }}
  - require:
    - pkg: maas_region_packages

/etc/maas/preseeds/curtin_userdata_amd64_generic_xenial:
  file.managed:
  - source: salt://maas/files/curtin_userdata_amd64_generic_xenial
  - template: jinja
  - user: root
  - group: root
  - mode: 644
  - context:
      salt_master_ip: {{ region.salt_master_ip }}
  - require:
    - pkg: maas_region_packages

/etc/maas/preseeds/curtin_userdata_arm64_generic_xenial:
  file.managed:
  - source: salt://maas/files/curtin_userdata_arm64_generic_xenial
  - template: jinja
  - user: root
  - group: root
  - mode: 644
  - context:
      salt_master_ip: {{ region.salt_master_ip }}
  - require:
    - pkg: maas_region_packages

/etc/maas/preseeds/curtin_userdata_amd64_generic_bionic:
  file.managed:
  - source: salt://maas/files/curtin_userdata_amd64_generic_bionic
  - template: jinja
  - user: root
  - group: root
  - mode: 644
  - context:
      salt_master_ip: {{ region.salt_master_ip }}
  - require:
    - pkg: maas_region_packages

Configure /root/.pgpass for MAAS:
  file.managed:
  - name: /root/.pgpass
  - source: salt://maas/files/pgpass
  - template: jinja
  - user: root
  - group: root
  - mode: 600

maas_region_services:
  service.running:
  - enable: true
  - names: {{ region.services }}
  - require:
    - cmd: maas_region_syncdb
  - watch:
    - file: /etc/maas/regiond.conf
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_region_syncdb:
  cmd.run:
  - names:
    - maas-region dbupgrade
  - require:
    - file: /etc/maas/regiond.conf
  {%- if grains['saltversioninfo'][0] >= 2017 and grains['saltversioninfo'][1] >= 7 %}
  - retry:
    attempts: 3
    interval: 5
    splay: 5
  {%- endif %}
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_warmup:
  module.run:
  - name: maasng.wait_for_http_code
# FIXME
  - url: "http://localhost:5240/MAAS"
# 405 - should be removed ,since twisted will be fixed
# Currently - api always throw 405=>500 even if request has been made with 'expected 'HEAD
  - expected: [200, 405]
  - require_in:
    - module: maas_set_admin_password
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_set_admin_password:
  cmd.run:
  - name: "maas createadmin --username {{ region.admin.username }} --password {{ region.admin.password }} --email {{ region.admin.email }} && touch /var/lib/maas/.setup_admin"
  - creates: /var/lib/maas/.setup_admin
  - require:
    - service: maas_region_services
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_login_admin:
  cmd.run:
  - name: "maas-region apikey --username {{ region.admin.username }} > /var/lib/maas/.maas_credentials"
  - require:
    - cmd: maas_set_admin_password
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_wait_for_racks_import_done:
  module.run:
  - name: maasng.sync_and_wait_bs_to_all_racks
  - require:
    - cmd: maas_login_admin
  - require_in:
    - module: maas_config
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_wait_for_region_import_done:
  module.run:
  - name: maasng.boot_resources_import
  - action: 'import'
  - wait: True
  - require:
    - cmd: maas_login_admin
  - require_in:
    - module: maas_wait_for_racks_import_done
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

maas_config:
  module.run:
  - name: maas.process_maas_config
  - require:
    - cmd: maas_login_admin
  {%- if grains.get('kitchen-test') %}
  - onlyif: /bin/false
  {%- endif %}

{% if region.get('boot_sources', False)  %}
  {%- for b_name, b_source in region.boot_sources.iteritems() %}
maas_region_boot_source_{{ b_name }}:
  maasng.boot_source_present:
    - url: {{ b_source.url }}
  {%- if b_source.keyring_data is defined %}
    - keyring_data: {{ b_source.keyring_data }}
  {%- endif %}
  {%- if b_source.keyring_file is defined %}
    - keyring_file: {{ b_source.keyring_file }}
  {%- endif %}
  {% if region.get('boot_sources_delete_all_others', False)  %}
    {# Collect exclude list, all other - will be removed #}
    {% set exclude_list=[] %}
    {%- for _, bs in region.boot_sources.iteritems() %} {% if bs.url is defined %} {% do exclude_list.append(bs.url) %} {% endif %} {%- endfor %}
    - delete_undefined_sources: True
    - delete_undefined_sources_except_urls: {{ exclude_list }}
  {%- endif %}
    - require_in:
      - module: maas_wait_for_region_import_done
    - require:
      - cmd: maas_login_admin
  {%- endfor %}
{%- endif %}

{##}
  {% if region.get('boot_sources_selections', False)  %}
  {%- for bs_name, bs_source in region.boot_sources_selections.iteritems() %}
maas_region_boot_sources_selection_{{ bs_name }}:
  maasng.boot_sources_selections_present:
    - bs_url: {{ bs_source.url }}
    - os: {{ bs_source.os }}
    - release: {{ bs_source.release|string }}
    - arches: {{ bs_source.arches|string }}
    - subarches: {{ bs_source.subarches|string }}
    - labels: {{ bs_source.labels }}
    - require_in:
      - module: maas_config
      - module: maas_wait_for_racks_import_done
    - require:
      - cmd: maas_login_admin
  {% if region.get('boot_sources', False)  %}
    {%- for b_name, _ in region.boot_sources.iteritems() %}
      - maas_region_boot_source_{{ b_name }}
    {% endfor %}
  {%- endif %}
  {%- endfor %}
  {%- endif %}
{##}

{%- if region.get('commissioning_scripts', False)  %}
/etc/maas/files/commisioning_scripts/:
  file.directory:
  - user: root
  - group: root
  - mode: 755
  - makedirs: true
  - require:
    - pkg: maas_region_packages

/etc/maas/files/commisioning_scripts/00-maas-05-simplify-network-interfaces:
  file.managed:
  - source: salt://maas/files/commisioning_scripts/00-maas-05-simplify-network-interfaces
  - mode: 755
  - user: root
  - group: root
  - require:
    - file: /etc/maas/files/commisioning_scripts/

maas_commissioning_scripts:
  module.run:
  - name: maas.process_commissioning_scripts
  - require:
    - cmd: maas_login_admin
{%- endif %}

{%- if region.get('fabrics', False)  %}
  {%- for _, fabric in region.fabrics.iteritems() %}
  {% set fabric_name=fabric.get('name', _) %}
# First, create fabrics
# Bakward-compat.name:

maas_fabrics_{{ fabric_name }}:
  maasng.fabric_present:
  - name: {{ fabric_name }}
  - description: {{ fabric.get('description', '') }}
  - require:
    - cmd: maas_login_admin

# Second, add VLAN into fabric's
    {%- for vlan_n, data in fabric.get('vlans',{}).iteritems() %}
maas_vlan{{ vlan_n }}_present_for_{{ fabric_name }}:
  maasng.vlan_present_in_fabric:
  - vlan: {{ vlan_n }}
  - mtu: {{ data.get('mtu', '') }}
  - fabric: {{ fabric_name }}
  - name: {{ data.get('name','') }}
  - description: {{ data.description }}
  - primary_rack: {{ data.get('primary_rack', '')  }}
    {%- endfor %}
  {%- endfor %}
{%- endif %}

# Create subnets
{%- if region.subnets is defined %}
  {%- for _, subnet in region.subnets.iteritems() %}
maas_create_subnet_{{ subnet.cidr }}:
  maasng.subnet_present:
  - cidr: {{ subnet.cidr }}
  - name: {{ subnet.get('name','') }}
  - fabric: {{ subnet.fabric }}
  - vlan: {{ subnet.get('vlan','') }}
  - gateway_ip: {{ subnet.gateway_ip }}
  - require:
    - cmd: maas_login_admin
    {%- if region.get('fabrics', False)  %}
    - maas_fabrics_{{ subnet.fabric }}
    {%- endif %}
# create ranges
    {%- for _r, iprange in subnet.get('ipranges',{}).iteritems() %}
maas_create_iprange_{{ _r }}:
  maasng.iprange_present:
  - name: {{ iprange.get('name', _r) }}
  - type_range: {{ iprange.type }}
  - start_ip: {{ iprange.start }}
  - end_ip: {{ iprange.end }}
  - subnet: {{ iprange.get('subnet', '' ) }}
  - comment: {{ iprange.get('comment', "") }}
  - require:
    - maas_create_subnet_{{ subnet.cidr }}
    {%- endfor %}
  {%- endfor %}
{%- endif %}

# Get back to fabrics again and enable DHCP
{%- if region.get('fabrics', False)  %}
  {%- for _, fabric in region.fabrics.iteritems() %}
    {%- for vlan_n, data in fabric.get('vlans',{}).iteritems() %}
    {% set fabric_name=fabric.get('name', _) %}
maas_vlan{{ vlan_n }}_present_for_{{ fabric_name }}_dhcp:
  maasng.vlan_present_in_fabric:
  - vlan: {{ vlan_n }}
  - mtu: {{ data.get('mtu', '') }}
  - fabric: {{ fabric_name }}
  - name: {{ data.get('name','') }}
  - description: {{ data.description }}
  - primary_rack: {{ data.get('primary_rack', '')  }}
  - dhcp_on: {{ data.get('dhcp','False') }}
    {%- endfor %}
  {%- endfor %}
{%- endif %}

{%- if region.get('devices', False)  %}
maas_devices:
  module.run:
  - name: maas.process_devices
  - require:
    - cmd: maas_login_admin
    {%- if region.get('subnets', False)  %}
    - module: maas_subnets
    {%- endif %}
{%- endif %}

{%- if region.get('dhcp_snippets', False)  %}
maas_dhcp_snippets:
  module.run:
  - name: maas.process_dhcp_snippets
  - require:
    - cmd: maas_login_admin
{%- endif %}

{%- if region.get('package_repositories', False)  %}
maas_package_repositories:
  module.run:
  - name: maas.process_package_repositories
  - require:
    - cmd: maas_login_admin
{%- endif %}

# FIXME
# This function usless since broken API logic in module.
# Should be refactored to be able work with regaiond-domain structure.
#maas_domain:
#  module.run:
#  - name: maas.process_domain
#  - require:
#    - cmd: maas_login_admin
#  {%- if grains.get('kitchen-test') %}
#  - onlyif: /bin/false
#  {%- endif %}

{%- if region.get('sshprefs', False)  %}
{%- for sshkey in region.sshprefs %}
{%- set idx = loop.index %}
maas_sshkey_{{ idx }}:
  maasng.sshkey_present:
  - name: {{ region.admin.username }}
  - sshkey: {{ sshkey }}
  - require:
    - cmd: maas_login_admin
{% endfor %}
{%- endif %}

{%- endif %}
