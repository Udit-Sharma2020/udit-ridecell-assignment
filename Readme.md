## CI

## Assignment 1
### Phase I:
- Create a new github public repo from [repo](https://github.com/kubernetes/examples/tree/master/guestbook-go)
- Create a container image using Github Action workflow for above project.
- Push that image to docker hub.

### Phase II:
- Deploy container image built in above step(Phase I) on local/any kubernetes cluster.

### Phase III:
- Prevent merging anything in main branch without review.
- Build container image only when one of the below conditions is true:
    - When PR get merged in main/master branch from any other branch.
    - When commit message contains `BUILD_CONTAINER_IMAGE` string
- Share the github repo link by replying to email where you got the assignments.