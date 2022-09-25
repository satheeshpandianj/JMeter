# Use vinsdocker base image
FROM satheeshpandianj/jmeterbase
MAINTAINER SATHEESH PANDIAN JEGANATHAN <satheeshpandianj@gmail.com>


ENV JMETER_VERSION 5.5
ENV JMETER_HOME /jmeter/apache-jmeter-${JMETER_VERSION}
ENV PATH $PATH:$JMETER_BIN


WORKDIR $JMETER_HOME

# Ports to be exposed from the container for JMeter Slaves/Server
EXPOSE 1099 50000

# Application to run on starting the container
ENTRYPOINT ${JMETER_HOME}/bin/jmeter-server \
                        -Dserver.rmi.localport=50000 \
                        -Dserver_port=1099 \
                        -Jserver.rmi.ssl.disable=true