#!/usr/bin/env bash
# Provisions inter-region Transit Gateway peering for the 3 stretch-cluster VPCs.
# Compatible with bash 3.2 (no associative arrays).
set -eo pipefail

KEYS=(east west eu)
REGIONS=(us-east-1 us-west-2 eu-west-1)
CLUSTERS=(rp-east rp-west rp-eu)
CIDRS=(10.10.0.0/16 10.20.0.0/16 10.30.0.0/16)

idx() { # index by key
  case "$1" in east) echo 0;; west) echo 1;; eu) echo 2;; esac
}
region_of() { echo "${REGIONS[$(idx $1)]}"; }
cluster_of() { echo "${CLUSTERS[$(idx $1)]}"; }
cidr_of() { echo "${CIDRS[$(idx $1)]}"; }

VPC_east= VPC_west= VPC_eu=
TGW_east= TGW_west= TGW_eu=
ATT_east= ATT_west= ATT_eu=
RT_east= RT_west= RT_eu=
PEER_east_west= PEER_east_eu= PEER_west_eu=

set_var() { eval "$1=\"$2\""; }
get_var() { eval "echo \"\$$1\""; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TAGSPEC_TGW="ResourceType=transit-gateway,Tags=[{Key=Project,Value=redpanda-stretch-validation},{Key=CreatedBy,Value=claude-code}]"
TAGSPEC_ATT="ResourceType=transit-gateway-attachment,Tags=[{Key=Project,Value=redpanda-stretch-validation},{Key=CreatedBy,Value=claude-code}]"
TAGSPEC_PEER="ResourceType=transit-gateway-attachment,Tags=[{Key=Project,Value=redpanda-stretch-validation},{Key=CreatedBy,Value=claude-code}]"

echo "=== 1) Look up VPC IDs from eksctl CFN outputs ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); C=$(cluster_of $K)
  V=$(aws cloudformation describe-stacks --region "$R" --stack-name "eksctl-${C}-cluster" \
    --query 'Stacks[0].Outputs[?OutputKey==`VPC`].OutputValue' --output text)
  set_var "VPC_$K" "$V"
  echo "$K: VPC=$V in $R"
done

echo "=== 2) Create TGW per region ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K)
  ASN=$((64512 + RANDOM % 1000))
  TGW=$(aws ec2 create-transit-gateway --region "$R" \
    --description "rp-stretch-${K}" \
    --options "AmazonSideAsn=${ASN},AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable,DnsSupport=enable" \
    --tag-specifications "$TAGSPEC_TGW" \
    --query 'TransitGateway.TransitGatewayId' --output text)
  set_var "TGW_$K" "$TGW"
  echo "$K: TGW=$TGW (ASN=$ASN)"
done

echo "=== 3) Wait for TGWs available ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); TGW=$(get_var "TGW_$K")
  while true; do
    s=$(aws ec2 describe-transit-gateways --region "$R" \
      --transit-gateway-ids "$TGW" --query 'TransitGateways[0].State' --output text)
    [ "$s" = "available" ] && break
    echo "  $K TGW state: $s"
    sleep 10
  done
  echo "$K: TGW ready"
done

echo "=== 4) Attach VPC to local TGW ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); V=$(get_var "VPC_$K"); TGW=$(get_var "TGW_$K")
  SUBNETS=$(aws ec2 describe-subnets --region "$R" \
    --filters "Name=vpc-id,Values=$V" "Name=tag:aws:cloudformation:logical-id,Values=SubnetPrivate*" \
    --query 'Subnets[].SubnetId' --output text)
  if [ -z "$SUBNETS" ]; then
    echo "  no SubnetPrivate* found, falling back to all subnets"
    SUBNETS=$(aws ec2 describe-subnets --region "$R" --filters "Name=vpc-id,Values=$V" --query 'Subnets[].SubnetId' --output text)
  fi
  ATT=$(aws ec2 create-transit-gateway-vpc-attachment --region "$R" \
    --transit-gateway-id "$TGW" --vpc-id "$V" \
    --subnet-ids $SUBNETS \
    --tag-specifications "$TAGSPEC_ATT" \
    --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
  set_var "ATT_$K" "$ATT"
  echo "$K: VPC attachment=$ATT subnets=$SUBNETS"
done

echo "=== 5) Wait for VPC attachments available ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); ATT=$(get_var "ATT_$K")
  while true; do
    s=$(aws ec2 describe-transit-gateway-vpc-attachments --region "$R" \
      --transit-gateway-attachment-ids "$ATT" \
      --query 'TransitGatewayVpcAttachments[0].State' --output text)
    [ "$s" = "available" ] && break
    echo "  $K state: $s"
    sleep 10
  done
done

echo "=== 6) Create inter-region peering ==="
for PAIR in "east west" "east eu" "west eu"; do
  A=${PAIR% *}; B=${PAIR#* }
  TGWA=$(get_var "TGW_$A"); TGWB=$(get_var "TGW_$B")
  RB=$(region_of $B)
  PA=$(aws ec2 create-transit-gateway-peering-attachment --region "$(region_of $A)" \
    --transit-gateway-id "$TGWA" \
    --peer-transit-gateway-id "$TGWB" \
    --peer-account-id "$ACCOUNT" \
    --peer-region "$RB" \
    --tag-specifications "$TAGSPEC_PEER" \
    --query 'TransitGatewayPeeringAttachment.TransitGatewayAttachmentId' --output text)
  set_var "PEER_${A}_${B}" "$PA"
  echo "  $A->$B peer=$PA"
done

echo "=== 7) Wait pendingAcceptance and accept ==="
for PAIR in "east west" "east eu" "west eu"; do
  A=${PAIR% *}; B=${PAIR#* }
  PA=$(get_var "PEER_${A}_${B}"); RB=$(region_of $B)
  while true; do
    s=$(aws ec2 describe-transit-gateway-peering-attachments --region "$RB" \
      --filters "Name=transit-gateway-attachment-id,Values=$PA" \
      --query 'TransitGatewayPeeringAttachments[0].State' --output text 2>/dev/null || echo "")
    [ "$s" = "pendingAcceptance" ] || [ "$s" = "available" ] && break
    echo "  $A->$B receiver state: $s"
    sleep 10
  done
  if [ "$s" = "pendingAcceptance" ]; then
    aws ec2 accept-transit-gateway-peering-attachment --region "$RB" \
      --transit-gateway-attachment-id "$PA" >/dev/null
    echo "  accepted $A->$B"
  fi
done

echo "=== 8) Wait peerings 'available' ==="
for PAIR in "east west" "east eu" "west eu"; do
  A=${PAIR% *}; B=${PAIR#* }
  PA=$(get_var "PEER_${A}_${B}"); RA=$(region_of $A)
  while true; do
    s=$(aws ec2 describe-transit-gateway-peering-attachments --region "$RA" \
      --filters "Name=transit-gateway-attachment-id,Values=$PA" \
      --query 'TransitGatewayPeeringAttachments[0].State' --output text)
    [ "$s" = "available" ] && break
    echo "  $A->$B: $s"
    sleep 15
  done
done

echo "=== 9) Add static routes in each TGW route table for remote CIDRs via peering ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); TGW=$(get_var "TGW_$K")
  RT=$(aws ec2 describe-transit-gateways --region "$R" \
    --transit-gateway-ids "$TGW" \
    --query 'TransitGateways[0].Options.AssociationDefaultRouteTableId' --output text)
  set_var "RT_$K" "$RT"
  for OTHER in "${KEYS[@]}"; do
    [ "$OTHER" = "$K" ] && continue
    PA=$(get_var "PEER_${K}_${OTHER}")
    [ -z "$PA" ] && PA=$(get_var "PEER_${OTHER}_${K}")
    # Associate the peering attachment with the default RT (TGW peerings aren't auto-associated)
    aws ec2 associate-transit-gateway-route-table --region "$R" \
      --transit-gateway-route-table-id "$RT" \
      --transit-gateway-attachment-id "$PA" 2>/dev/null || true
    aws ec2 create-transit-gateway-route --region "$R" \
      --destination-cidr-block "$(cidr_of $OTHER)" \
      --transit-gateway-route-table-id "$RT" \
      --transit-gateway-attachment-id "$PA" >/dev/null 2>&1 \
      && echo "  $K: route $(cidr_of $OTHER) -> $PA" \
      || echo "  $K: route $(cidr_of $OTHER) (already exists or pending)"
  done
done

echo "=== 10) VPC route tables: route remote CIDRs via local TGW ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); V=$(get_var "VPC_$K"); TGW=$(get_var "TGW_$K")
  RTS=$(aws ec2 describe-route-tables --region "$R" --filters "Name=vpc-id,Values=$V" \
    --query 'RouteTables[].RouteTableId' --output text)
  for RT in $RTS; do
    for OTHER in "${KEYS[@]}"; do
      [ "$OTHER" = "$K" ] && continue
      OUT=$(aws ec2 create-route --region "$R" \
        --route-table-id "$RT" \
        --destination-cidr-block "$(cidr_of $OTHER)" \
        --transit-gateway-id "$TGW" 2>&1 || true)
      if echo "$OUT" | grep -q "true"; then
        echo "  $K $RT -> $(cidr_of $OTHER) via TGW"
      else
        echo "  $K $RT -> $(cidr_of $OTHER) skipped (already exists or N/A)"
      fi
    done
  done
done

echo "=== 11) Open SGs for ports 8443 & 33145 from peer CIDRs ==="
for K in "${KEYS[@]}"; do
  R=$(region_of $K); V=$(get_var "VPC_$K"); C=$(cluster_of $K)
  # eksctl creates *Node* SGs and *ClusterSharedNode* SGs
  SGS=$(aws ec2 describe-security-groups --region "$R" \
    --filters "Name=vpc-id,Values=$V" \
              "Name=group-name,Values=*${C}*" \
    --query 'SecurityGroups[].GroupId' --output text)
  for SG in $SGS; do
    for OTHER in "${KEYS[@]}"; do
      [ "$OTHER" = "$K" ] && continue
      for PORT in 8443 33145; do
        OUT=$(aws ec2 authorize-security-group-ingress --region "$R" \
          --group-id "$SG" --protocol tcp --port "$PORT" \
          --cidr "$(cidr_of $OTHER)" 2>&1 || true)
        if echo "$OUT" | grep -qi "InvalidPermission.Duplicate"; then
          : # already exists, silent
        elif echo "$OUT" | grep -q "Return"; then
          echo "  $K $SG :$PORT from $(cidr_of $OTHER)"
        fi
      done
    done
  done
done

echo "=== TGW setup complete ==="
echo "TGWs: east=$(get_var TGW_east) west=$(get_var TGW_west) eu=$(get_var TGW_eu)"
echo "Peerings: east_west=$(get_var PEER_east_west) east_eu=$(get_var PEER_east_eu) west_eu=$(get_var PEER_west_eu)"
