job "hz-service" {
  datacenters = ["dc1"]
  type        = "service"

  # Specify this job to have rolling updates, with 30 second intervals.
  update {
    stagger      = "30s"
    max_parallel = 1
  }

  # Deploy on separate nodes only
  constraint {
    operator = "distinct_hosts"
    value = "true"
  }
  # A group defines a series of tasks that should be co-located
  # on the same client (host). All tasks within a group will be
  # placed on the same host.
  group "service" {
    # Specify the number of these tasks we want.
    count = 2

    restart {
      attempts = 1
      interval = "30s"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      mode = "cni/weave"

      port "api" {
        to = 3000
      }

      port "cl" {
        to = 5701
      }

      port "cl2" {
        to = 5702
      }
    }

    task "api" {
      driver = "docker"
      leader = true
      config {
        image = "coh-service:local"
        network_mode = "cni/weave"
        ports = ["api"]

        mount {
          type   = "bind"
          source = "local/hosts"
          target = "/var/services/coh-service/hosts"
        }

        mount {
          type   = "bind"
          source = "local/hz.xml"
          target = "/var/services/coh-service/hz.xml"
        }
        memory_hard_limit = 756
      }

      env {
        JDK_JAVA_OPTIONS = "--add-modules java.se --add-exports java.base/jdk.internal.ref=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-opens java.base/sun.nio.ch=ALL-UNNAMED --add-opens java.management/sun.management=ALL-UNNAMED --add-opens jdk.management/com.sun.management.internal=ALL-UNNAMED"
        JAVA_TOOL_OPTIONS = "-Dhazelcast.config=./hz.xml"
        CONSUL_HTTP_ADDR ="http://${attr.driver.docker.bridge_ip}:8500"
      }

      resources {
        cpu    = 1000
        memory = 512
      }

      service {
        name = "hz-service-api"
        tags = ["api"]
        port = "api"

        check {
          type     = "http"
          port = "api"
          path = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "hz-cluster"
        tags = ["cluster"]
        port = "cl"

        check {
          type     = "tcp"
          port = "api"
          interval = "10s"
          timeout  = "2s"
        }
      }

      template {
        data = <<EOH
          127.0.0.1	localhost
          172.17.0.2 {{ env "NOMAD_ALLOC_ID" }}
        EOH

        destination = "local/hosts"
      }

      template {
        data = <<EOH
hazelcast:
  cluster-name: hz-service-cluster
  properties:
    hazelcast.logging.type: slf4j
  management-center:
    scripting-enabled: false
  network:
    port:
      auto-increment: true
      port-count: 10
      port: 5701
    outbound-ports:
      - 35701-35710
    join:
      multicast:
        enabled: true
      tcp-ip:
        enabled: false
        member-list:
          - 127.0.0.1
          - 172.16.30.12/24
          - hzmain.connect.consul
      discovery-strategies:
        - discovery-strategy:
          enabled: false
          class: org.bitsofinfo.hazelcast.discovery.consul.ConsulDiscoveryStrategy
          properties:
            consul-host: ${attr.driver.docker.bridge_ip}
            consul-port: 8500
            consul-service-name: hzmain
            consul-discovery-delay-ms: 10000


  map:
    users:
      time-to-live-seconds: 240
        EOH

        destination = "local/hz.yml"
      }

      template {
        data = <<EOH
<hazelcast xsi:schemaLocation="http://www.hazelcast.com/schema/config http://www.hazelcast.com/schema/config/hazelcast-config-4.2.xsd"
           xmlns="http://www.hazelcast.com/schema/config"
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <cluster-name>hz-service-cluster</cluster-name>
    <management-center scripting-enabled="true" />
    <properties>
        <property name="hazelcast.logging.type">slf4j</property>
        <property name="hazelcast.discovery.enabled">false</property>
    </properties>
    <network>
        <port auto-increment="true" port-count="2">5701</port>
        <outbound-ports>
            <ports>35701</ports>
            <ports>35702</ports>
        </outbound-ports>
        <join>
          <multicast enabled="true">
                <multicast-group>224.2.2.3</multicast-group>
                <multicast-port>6700</multicast-port>
	        </multicast>
          <tcp-ip enabled="false">
                <member>hz-cluster.service.consul</member>
                <!--member>127.0.0.1:9090</member-->
            </tcp-ip>
          <discovery-strategies>
              <discovery-strategy enabled="false" class="org.bitsofinfo.hazelcast.discovery.consul.ConsulDiscoveryStrategy">

                  <properties>
                      <property name="consul-host">172.17.0.1</property>
                      <property name="consul-port">8500</property>
                      <property name="consul-service-name">hz-cluster</property>
                      <property name="consul-healthy-only">false</property>
                      <property name="consul-service-tags">hazelcast, test1</property>
                      <property name="consul-discovery-delay-ms">10000</property>

                      <property name="consul-acl-token"></property>
                      <property name="consul-ssl-enabled">false</property>
                      <property name="consul-ssl-server-cert-file-path"></property>
                      <property name="consul-ssl-server-cert-base64"></property>
                      <property name="consul-ssl-server-hostname-verify">true</property>

                      <property name="consul-registrator">org.bitsofinfo.hazelcast.discovery.consul.DoNothingRegistrator</property>
                      <property name="consul-registrator-config"></property>

                  </properties>
              </discovery-strategy>
          </discovery-strategies>
        </join>
    </network>
</hazelcast>
        EOH

        destination = "local/hz.xml"
      }



      /* service {
        name = "hz-cl"
        tags = ["cluster-main"]
        port = "cl"

        check {
          type     = "tcp"
          port = "cl"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "hz-cl2"
        tags = ["cluster-listen"]
        port = "cl2"

        check {
          type     = "tcp"
          port = "cl2"
          interval = "10s"
          timeout  = "2s"
        }
      } */
    }
  }
}
