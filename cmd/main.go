package main

import (
	"context"
	"embed"
	"os"

	"k8s.io/client-go/kubernetes/scheme"

	restclient "k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"open-cluster-management.io/addon-framework/pkg/addonfactory"
	"open-cluster-management.io/addon-framework/pkg/addonmanager"

	otelv1alpha1 "github.com/open-telemetry/opentelemetry-operator/apis/v1alpha1"
	projectsv1 "github.com/openshift/api/project/v1"
	operatorsv1 "github.com/operator-framework/api/pkg/operators/v1"
	operatorsv1alpha1 "github.com/operator-framework/api/pkg/operators/v1alpha1"
)

//go:embed manifests
var FS embed.FS

const (
	addonName = "otel-addon"
)

func main() {
	kubeConfig, err := restclient.InClusterConfig()
	if err != nil {
		os.Exit(1)
	}
	addonMgr, err := addonmanager.New(kubeConfig)
	if err != nil {
		klog.Errorf("unable to setup addon manager: %v", err)
		os.Exit(1)
	}

	// Necessary to reconcile OpenTelemetryCollectors
	err = otelv1alpha1.AddToScheme(scheme.Scheme)
	if err != nil {
		klog.Errorf("error while adding the otel types to the schema: %v", err)
		os.Exit(1)
	}

	// Necessary to reconcile Projects
	err = projectsv1.AddToScheme(scheme.Scheme)
	if err != nil {
		klog.Errorf("error while adding the project types to the schema: %v", err)
		os.Exit(1)
	}

	// Necessary to reconcile OperatorGroups
	err = operatorsv1.AddToScheme(scheme.Scheme)
	if err != nil {
		klog.Errorf("error while adding the operatorgroup types to the schema: %v", err)
		os.Exit(1)
	}
	// Necessary to reconcile Subscriptions
	err = operatorsv1alpha1.AddToScheme(scheme.Scheme)
	if err != nil {
		klog.Errorf("error while adding the subscription types to the schema: %v", err)
		os.Exit(1)
	}

	agentAddon, err := addonfactory.NewAgentAddonFactory(addonName, FS, "manifests").
		WithScheme(scheme.Scheme).
		BuildTemplateAgentAddon()
	if err != nil {
		klog.Errorf("failed to build agent addon %v", err)
		os.Exit(1)
	}

	err = addonMgr.AddAgent(agentAddon)
	if err != nil {
		klog.Errorf("failed to add addon agent: %v", err)
		os.Exit(1)
	}

	ctx := context.Background()
	go addonMgr.Start(ctx)

	<-ctx.Done()
}
