job "another-coherence-service" {
  datacenters = ["dc1"]
  type        = "service"

  # Specify this job to have rolling updates, with 30 second intervals.
  update {
    stagger      = "20s"
    max_parallel = 1
  }

  # Deploy on separate nodes only
  constraint {
    operator = "distinct_hosts"
    value = "true"
  }

  # Group
  group "service" {
    count = 2

    restart {
      attempts = 1
      interval = "30s"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      # The magic of cross container network interfacing that makes this all possible
      mode = "cni/weave"

      port "api" {
        to = 3000
      }

      port "cluster-port" {
        to = 3100
      }

      port "cluster-port2" {
        to = 3101
      }

      port "cluster-port3" {
        to = 7574
      }
    }

    # Registering just to enable proper DNS resolution
   service {
      name = "cluster-internal"
      port = "cluster-port"
      address_mode = "alloc"
      # Fix from this PR https://github.com/hashicorp/nomad/issues/8801 allows proper DNS lookups
    }

    service {
      name = "cluster-internal-secondary"
      port = "cluster-port2"
      address_mode = "alloc"
    }

    task "api" {
      driver = "docker"
      leader = true
      config {
        image = "coh-service:local"
        ports = ["api", "cluster-port", "cluster-port2"]

        mount {
          type   = "bind"
          source = "local/coherence-config.xml"
          target = "/var/services/coh-service/coherence-config.xml"
        }
        memory_hard_limit = 756
      }

      env {
        JAVA_TOOL_OPTIONS = "-Dcoherence.override=./coherence-config.xml -Dcoh.alloc.id=${NOMAD_ALLOC_INDEX} -Dcoherence.cluster=coh-cluster-poc -Dcoherence.mode=prod -Djava.net.preferIPv4Stack=true"
        CONSUL_HTTP_ADDR ="http://${attr.driver.docker.bridge_ip}:8500"
      }

      resources {
        cpu    = 1000
        memory = 512
      }

      service {
        name = "cluster-external"
        port = "cluster-port"
      }

      service {
        name = "cluster-external-secondary"
        port = "cluster-port2"
      }
      # The health API

      service {
        name = "another-coh-service-api"
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

      # Coherence config file
      template {
        data = <<EOH
<?xml version='1.0'?>

          <coherence xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    xmlns="http://xmlns.oracle.com/coherence/coherence-operational-config"
                    xsi:schemaLocation="http://xmlns.oracle.com/coherence/coherence-operational-config coherence-operational-config.xsd">

              <cluster-config>
                  <member-identity>
                      <cluster-name system-property="coherence.cluster">coh-cluster-poc</cluster-name>
                      <role-name>COH_ROLE</role-name>
                  </member-identity>

                    <unicast-listener>
                      <!--socket-provider>udp</socket-provider-->
                      <well-known-addresses>
                          <address-provider>
                              <class-name>com.beerduo.service.pg.coh.RefreshableConsulAddressProvider</class-name>
                              <init-params>
                                  <init-param>
                                      <param-type>java.lang.String</param-type>
                                      <param-value system-property="coh.clnames">cluster-external,cluster-external-secondary</param-value>
                                  </init-param>
                              </init-params>
                          </address-provider>
                      </well-known-addresses>
                      <!--machine-id system-property="coh.alloc.id">1</machine-id-->
                      <!--address system-property="coh.uni.ip">10.1.10.1/24</address-->
                      <port system-property="coh.main.port">3100</port>
                  </unicast-listener>

                  <!--socket-providers>
                      <socket-provider id="tcp">
                          <tcp/>
                      </socket-provider>
                  </socket-providers-->
              </cluster-config>

              <logging-config>
                  <destination>slf4j</destination>
                  <logger-name>MyCoh</logger-name>
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



    }
  }
}
