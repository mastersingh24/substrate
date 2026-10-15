// ate-selector sets (or clears) an actor's worker_selector, which takes
// effect on its next ResumeActor. kubectl-ate has no command for it.
//
//	ate-selector -context agent-substrate -atespace cred-test -actor NAME key=value
//	ate-selector -context agent-substrate -atespace cred-test -actor NAME -clear
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/agent-substrate/substrate/internal/ateclient"
	"github.com/agent-substrate/substrate/pkg/proto/ateapipb"
)

func main() {
	kctx := flag.String("context", "", "kubeconfig context")
	atespace := flag.String("atespace", "", "actor atespace")
	actor := flag.String("actor", "", "actor name")
	clear := flag.Bool("clear", false, "remove the selector")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	c, err := ateclient.NewClient(ctx, "", *kctx, "", "", false)
	if err != nil {
		log.Fatal(err)
	}
	defer c.Close()

	a, err := c.GetActor(ctx, &ateapipb.GetActorRequest{Actor: &ateapipb.ObjectRef{Atespace: *atespace, Name: *actor}})
	if err != nil {
		log.Fatal(err)
	}
	if *clear {
		a.WorkerSelector = nil
	} else {
		labels := map[string]string{}
		for _, kv := range flag.Args() {
			k, v, ok := strings.Cut(kv, "=")
			if !ok {
				log.Fatalf("want key=value, got %q", kv)
			}
			labels[k] = v
		}
		a.WorkerSelector = &ateapipb.Selector{MatchLabels: labels}
	}
	u, err := c.UpdateActor(ctx, &ateapipb.UpdateActorRequest{Actor: a})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s/%s worker_selector=%v version=%d\n", *atespace, *actor, u.GetWorkerSelector().GetMatchLabels(), u.GetMetadata().GetVersion())
}
