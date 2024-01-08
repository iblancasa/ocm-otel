package main

import (
	"context"
	"embed"
	"encoding/base64"
	"fmt"
	"os"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"

	restclient "k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"open-cluster-management.io/addon-framework/pkg/addonfactory"
	"open-cluster-management.io/addon-framework/pkg/addonmanager"

	otelv1alpha1 "github.com/open-telemetry/opentelemetry-operator/apis/v1alpha1"
	projectsv1 "github.com/openshift/api/project/v1"
	operatorsv1 "github.com/operator-framework/api/pkg/operators/v1"
	operatorsv1alpha1 "github.com/operator-framework/api/pkg/operators/v1alpha1"
	addonapiv1alpha1 "open-cluster-management.io/api/addon/v1alpha1"
	clusterv1 "open-cluster-management.io/api/cluster/v1"
)

//go:embed manifests
var FS embed.FS

type userValues struct {
	MTLS mTLS `json:"mTLS"`
}

type mTLS struct {
	Key      string `json:"key"`
	Cert     string `json:"cert"`
	CABundle string `json:"ca"`
}

const (
	addonName = "otel-addon"
	defaultInstallationNamespace = "open-cluster-management-agent-addon"
)

func GetDefaultValues(cluster *clusterv1.ManagedCluster,
	addon *addonapiv1alpha1.ManagedClusterAddOn) (addonfactory.Values, error) {
	installNamespace := addon.Spec.InstallNamespace
	if len(installNamespace) == 0 {
		installNamespace = defaultInstallationNamespace
	}

	manifestConfig := struct {
		ClusterName             string
		AddonInstallNamespace   string 
	}{
		AddonInstallNamespace: installNamespace,
		ClusterName:           cluster.Name,
	}

	return addonfactory.StructToValues(manifestConfig), nil
}


func GetMTLSSecretValues(kubeClient kubernetes.Interface) addonfactory.GetValuesFunc {
	return func(
		cluster *clusterv1.ManagedCluster,
		addon *addonapiv1alpha1.ManagedClusterAddOn,
	) (addonfactory.Values, error) {
		overrideValues := addonfactory.Values{}
		secret, err := kubeClient.CoreV1().Secrets(cluster.Name).Get(context.Background(), cluster.Name, metav1.GetOptions{})
		if err != nil {
			return nil, err
		}

		key, ok := secret.Data["tls.key"]
		if !ok {
			return nil, fmt.Errorf("no tls.key in secret %s/%s", cluster.Name, cluster.Name)
		}

		cert, ok := secret.Data["tls.crt"]
		if !ok {
			return nil, fmt.Errorf("no tls.crt in secret %s/%s", cluster.Name, cluster.Name)
		}

		ca, ok := secret.Data["ca.crt"]
		if !ok {
			return nil, fmt.Errorf("no tls.crt in secret %s/%s", cluster.Name, cluster.Name)
		}

		userJsonValues := userValues{
			MTLS: mTLS{
				Key:  base64.StdEncoding.EncodeToString(key),
				Cert: base64.StdEncoding.EncodeToString(cert),
				CABundle: base64.StdEncoding.EncodeToString(ca),
			},
		}
		values, err := addonfactory.JsonStructToValues(userJsonValues)
		if err != nil {
			return nil, err
		}
		overrideValues = addonfactory.MergeValues(overrideValues, values)

		return overrideValues, nil
	}
}


	

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

	kubeClient, err := kubernetes.NewForConfig(kubeConfig)
	if err != nil {
		klog.Errorf("unable to create the kubernetes client: %v", err)
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
		WithGetValuesFuncs(
			GetDefaultValues,
			GetMTLSSecretValues(kubeClient),
		).
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
	
	// Create a channel for errors
	errChan := make(chan error, 1)

	// Run addonMgr.Start in a goroutine
	go func() {
		err := addonMgr.Start(ctx)
		if err != nil {
			// Send the error to the channel
			errChan <- err
		}
		// Close the channel when finished
		close(errChan)
	}()

	// Check for an error
	if err := <-errChan; err != nil {
		// Handle the error
		klog.Fatalf("addonMgr failed to start: %v", err)
	}

	<-ctx.Done()
}
