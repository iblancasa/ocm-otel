
# Use distroless as minimal base image to package the addon binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
FROM gcr.io/distroless/static:nonroot
WORKDIR /

ARG TARGETARCH

# Copy binary built on the host
COPY bin/addon_${TARGETARCH} addon

USER 65532:65532

ENTRYPOINT ["/addon"]
