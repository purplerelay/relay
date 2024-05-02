#!/bin/bash

# set -x
TAG_KEY="Name"
TAG_VALUE="purplerelay-VPC"
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)
path_files='./vpc_regions'
num_region=0

list_vpcs_with_tag() {
    region=$1
    aws ec2 describe-vpcs --region $region \
        --filters "Name=tag-key,Values=$TAG_KEY" "Name=tag-value,Values=$TAG_VALUE" \
        --query "Vpcs[].VpcId" --output text
}

get_file() {
    region=$1
    cat $path_files/$1
}

mkdir $path_files

for region in $REGIONS; do
    vpcs=$(list_vpcs_with_tag $region)

    if [ -z "$vpcs" ]; then
        echo "No VPC with a tag '$TAG_KEY:$TAG_VALUE' found in the $region."
    else
        echo "$vpcs" > ./vpc_regions/$region
        num_region=$((num_region + 1))

    fi
done

list_files=$(ls $path_files)

echo "Regions found: $num_region"

for file_region in $list_files; do
    array_region+=($file_region)
done

for ((i=0; i<num_region; i++)); do
    vpc1=$(get_file ${array_region[i]})
    
    for ((j=i+1; j<num_region; j++)); do
        vpc2=$(get_file ${array_region[j]})            
        
        peering_exists1=$(aws ec2 describe-vpc-peering-connections --region ${array_region[i]} \
            --filters "Name=requester-vpc-info.vpc-id,Values=$vpc1" "Name=accepter-vpc-info.vpc-id,Values=$vpc2" \
            --query "VpcPeeringConnections[?Status.Code=='active' || Status.Code=='pending-acceptance']" --output text)

        peering_exists2=$(aws ec2 describe-vpc-peering-connections --region ${array_region[i]} \
            --filters "Name=requester-vpc-info.vpc-id,Values=$vpc2" "Name=accepter-vpc-info.vpc-id,Values=$vpc1" \
            --query "VpcPeeringConnections[?Status.Code=='active' || Status.Code=='pending-acceptance']" --output text)

        if [ -z "$peering_exists1" ] && [ -z "$peering_exists2" ]; then
            if [ ${#array_region[i]} -gt 0 ] && [ ${#array_region[j]} -gt 0 ]; then
        
                echo "Creating VPC Peering between VPC $vpc1 in region ${array_region[i]} and VPC $vpc2 in region ${array_region[j]}..."
                peering_id=$(aws ec2 create-vpc-peering-connection \
                    --region ${array_region[i]} \
                    --vpc-id $vpc1 \
                    --peer-vpc-id $vpc2 \
                    --peer-region ${array_region[j]} \
                    --output text \
                    --query 'VpcPeeringConnection.VpcPeeringConnectionId')
                
                if [ -n "$peering_id" ]; then
                    echo "VPC Peering created with ID: $peering_id"
                    echo "Wait for the connection between VPCs to complete..."
                    echo "peering id: $peering_id"
                    sleep 15
                    aws ec2 accept-vpc-peering-connection \
                        --region ${array_region[j]} \
                        --vpc-peering-connection-id $peering_id

                    echo "VPC Peering accepted in the region ${array_region[j]}"
                    sleep 10

                    echo "Configuring route table..."
                    route_table_id1=$(aws ec2 describe-route-tables \
                                        --region ${array_region[i]} \
                                        --filters "Name=tag:Name,Values=purplerelay-PrivateRouteTable" \
                                        --query "RouteTables[].RouteTableId" \
                                        --output text)

                    route_table_id2=$(aws ec2 describe-route-tables \
                                        --region ${array_region[j]} \
                                        --filters "Name=tag:Name,Values=purplerelay-PrivateRouteTable" \
                                        --query "RouteTables[].RouteTableId" \
                                        --output text)

                    if [ -n "$route_table_id1" ] && [ -n "$route_table_id2" ]; then

                        cidr_block1=$(aws ec2 describe-vpcs \
                            --region ${array_region[i]} \
                            --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=purplerelay-VPC" \
                            --query "Vpcs[].CidrBlock" \
                            --output text)

                        cidr_block2=$(aws ec2 describe-vpcs \
                            --region ${array_region[j]} \
                            --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=purplerelay-VPC" \
                            --query "Vpcs[].CidrBlock" \
                            --output text)

                        aws ec2 create-route \
                            --region ${array_region[i]} \
                            --route-table-id $route_table_id1 \
                            --destination-cidr-block $cidr_block2 \
                            --vpc-peering-connection-id $peering_id

                        sleep 20

                        aws ec2 create-route \
                            --region ${array_region[j]} \
                            --route-table-id $route_table_id2 \
                            --destination-cidr-block $cidr_block1 \
                            --vpc-peering-connection-id $peering_id

                        echo "Route table configuration for regions ${array_region[i]} and ${array_region[j]} finalized"
                        sleep 10
                    else
                        echo "Route table not found."
                    fi   
                else
                    echo "Failed to create VPC Peering between VPC $vpc1 in region ${array_region[i]} and VPC $vpc2 in region ${array_region[j]}."
                fi
            else
                echo "missing region for VPC peering creation"
            fi
        else
            echo "VPC Peering already exists between VPC $vpc1 in region ${array_region[i]} and VPC $vpc2 in region ${array_region[j]}. Skipping..."
        fi
    done
done

rm -rf $path_files