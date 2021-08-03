job "coherence-service" {
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
      port "api" {
        to = 3000
      }

      port "cl" {
        static = 3100
      }

      port "cl2" {
        static = 3101
      }

    }

    task "api" {
      driver = "docker"
      leader = true
      config {
        image = "coh-service:local"
        network_mode = "host"
        ports = ["api"]

        mount {
          type   = "bind"
          source = "local/hosts"
          target = "/var/services/coh-service/hosts"
        }

        mount {
          type   = "bind"
          source = "local/coherence-config.xml"
          target = "/var/services/coh-service/coherence-config.xml"
        }
        memory_hard_limit = 1200
      }

      env {
        JAVA_TOOL_OPTIONS = "-Dcoherence.override=./coherence-config.xml -Dcoh.alloc.id=${NOMAD_ALLOC_INDEX} -Dcoherence.cluster=lecluster -Djava.net.preferIPv4Stack=true -Dnode.wka=${HOSTNAME} -Dcoherence.unicastip=${NOMAD_IP_api}"
        CONSUL_HTTP_ADDR ="http://${attr.driver.docker.bridge_ip}:8500"
      }

      resources {
        cpu    = 1000
        memory = 800
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
<?xml version='1.0'?>

          <coherence xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    xmlns="http://xmlns.oracle.com/coherence/coherence-operational-config"
                    xsi:schemaLocation="http://xmlns.oracle.com/coherence/coherence-operational-config coherence-operational-config.xsd">

              <cluster-config>
                  <member-identity>
                      <cluster-name system-property="coherence.cluster">coh-cluster-poc</cluster-name>
                  </member-identity>

                  <unicast-listener>
                      <socket-provider>tcp</socket-provider>
                      <well-known-addresses>
                          <!--address id="1">172.16.30.0/24</address>
                          <address id="dns">10.1.10.20</address-->

                          <address-provider>
                              <class-name>com.beerduo.service.pg.coh.RefreshableConsulAddressProvider</class-name>
                              <init-params>
                                  <init-param>
                                      <param-type>java.lang.String</param-type>
                                      <param-value system-property="coh.clustername">coh-cl</param-value>
                                  </init-param>
                              </init-params>
                          </address-provider>

                      </well-known-addresses>
                      <machine-id system-property="coh.alloc.id">1</machine-id>
                      <address system-property="coherence.unicastip">172.16.30.0/24</address>
                      <port system-property="coherence.clusterport">3100</port>
                  </unicast-listener>

                  <!--multicast-listener>
                      <time-to-live system-property="coherence.ttl">10</time-to-live>
                      <address system-property="coherence.clusteraddress">0.0.0.0</address>
                      <port system-property="coherence.clusterport">3101</port>
                      <multicast-threshold-percent>100</multicast-threshold-percent>
                  </multicast-listener-->

                  <socket-providers>
                      <socket-provider id="tcp">
                          <tcp/>
                      </socket-provider>
                  </socket-providers>
              </cluster-config>

              <logging-config>
                  <destination>slf4j</destination>
                  <logger-name>Палочка Коха</logger-name>
                  <message-format>[{thread}] {text}</message-format>
              </logging-config>

              <configurable-cache-factory-config>
                  <init-params>
                      <init-param>
                          <param-type>java.lang.String</param-type>
                          <param-value system-property="coherence.cacheconfig">cache-config.xml</param-value>
                      </init-param>
                  </init-params>
              </configurable-cache-factory-config>

          </coherence>
        EOH

        destination = "local/coherence-config.xml"
      }

      service {
        name = "coh-service-api"
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
        name = "coh-cl"
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
        name = "coh-cl2"
        tags = ["cluster-listen"]
        port = "cl2"

        check {
          type     = "tcp"
          port = "cl2"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
