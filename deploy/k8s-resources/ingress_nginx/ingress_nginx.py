import pulumi
from pulumi_kubernetes.core.v1 import Namespace
from pulumi_kubernetes.helm.v3 import Chart, ChartOpts, FetchOpts

config = pulumi.Config()


def deploy():
    # Create Ingress Nginx namespace if it doesn't already exist
    ingress_namespace = Namespace(
        "ingress-nginx-ns",
        metadata={"name": "ingress-nginx-ns"},
        opts=pulumi.ResourceOptions( depends_on=[]),
    )

    # Deploy Ingress Nginx using Helm Chart
    nginx_chart = Chart(
        "ingress-nginx",
        ChartOpts(
            chart="ingress-nginx",
            version=config.require("ingressNginxVersion"),
            fetch_opts=FetchOpts(repo="https://kubernetes.github.io/ingress-nginx"),
            namespace=ingress_namespace.metadata["name"],
            values={
                "controller": {
                    "watchIngressWithoutClass": True,
                    "ingressClassResource": {"default": True},
                    "service": {
                        "type": "NodePort",
                        "nodePorts": {"http": 31080, "https": 31443},
                    },
                    "publishService": {"enabled": False},
                },
            },
        ),
        opts=pulumi.ResourceOptions(
             depends_on=[ingress_namespace]
        ),
    )

    return nginx_chart
