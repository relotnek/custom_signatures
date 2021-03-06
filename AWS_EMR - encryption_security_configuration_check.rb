#
# Copyright (c) 2013, 2014, 2015, 2016, 2017. Evident.io (Evident). All Rights Reserved. 
#   Evident.io shall retain all ownership of all right, title and interest in and to 
#   the Licensed Software, Documentation, Source Code, Object Code, and API's ("Deliverables"), 
#   including (a) all information and technology capable of general application to Evident.io's customers; 
#   and (b) any works created by Evident.io prior to its commencement of any Services for Customer. 
#
# Upon receipt of all fees, expenses and taxes due in respect of the relevant Services, 
#   Evident.io grants the Customer a perpetual, royalty-free, non-transferable, license to 
#   use, copy, configure and translate any Deliverable solely for internal business operations of the Customer 
#   as they relate to the Evident.io platform and products, 
#   and always subject to Evident.io's underlying intellectual property rights.
#
# IN NO EVENT SHALL EVIDENT.IO BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, 
#   INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF 
#   THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, 
#   EVEN IF EVIDENT.IO HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# EVIDENT.IO SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
#  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. 
#  THE SOFTWARE AND ACCOMPANYING DOCUMENTATION, IF ANY, PROVIDED HEREUNDER IS PROVIDED "AS IS". 
#  EVIDENT.IO HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
#

# Description:
# Check for Cluster's Security Configuration (Encryption)
#
# This custom signature requires additional permission:
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "EMRInspect",
#       "Effect": "Allow",
#       "Action": [
#         "elasticmapreduce:ListClusters",
#         "elasticmapreduce:DescribeCluster",
#         "elasticmapreduce:DescribeSecurityConfiguration"
#       ],
#       "Resource": [
#         "*"
#       ]
#     }
#   ]
# }
#
# 
# Default Conditions:
# - PASS: EMR cluster has both in-transit and at-rest encryption enabled
# - FAIL: EMR cluster has no security configuration (encryption) set
# - FAIL: EMR cluster has only in-transit or at-rest encryption enabled
# 
#
# Resolution/Remediation:
# As of Sept 2017, you can only specify the security configuration when launching a cluster and there is
# no option to modify the existing cluster's security configuration
# You might need to re-launch the cluster with the proper security configuration
#

#    ______     ___     ____  _____   ________   _____     ______   
#  .' ___  |  .'   `.  |_   \|_   _| |_   __  | |_   _|  .' ___  |  
# / .'   \_| /  .-.  \   |   \ | |     | |_ \_|   | |   / .'   \_|  
# | |        | |   | |   | |\ \| |     |  _|      | |   | |   ____  
# \ `.___.'\ \  `-'  /  _| |_\   |_   _| |_      _| |_  \ `.___]  | 
#  `.____ .'  `.___.'  |_____|\____| |_____|    |_____|  `._____.'  
# Configurable options                                                                  
@options = {
  # When a resource has one or more matching tags, the resource will be excluded from the checks
  # and a PASS alert is generated
  # Example:
  # exclude_on_tag: [
  #     {key: "environment", value: "demo"},
  #     {key: "environment", value: "dev*"}
  # ]
  # For wildcard, use *  . If set value: "*", it will match any value inside of the tag
  exclude_on_tag: [
    {key: "environment", value: "test*"}
  ],

  # If set to true, FAIL alert will be generated if
  # in-tansit encryption is not enabled
  require_in_transit_encryption: true ,

  # If set to true, FAIL alert will be generated if
  # at-rest encryption is not enabled
  require_at_rest_encryption: true ,

}

#    ______   ____  ____   ________     ______   ___  ____     ______   
#  .' ___  | |_   ||   _| |_   __  |  .' ___  | |_  ||_  _|  .' ____ \  
# / .'   \_|   | |__| |     | |_ \_| / .'   \_|   | |_/ /    | (___ \_| 
# | |          |  __  |     |  _| _  | |          |  __'.     _.____`.  
# \ `.___.'\  _| |  | |_   _| |__/ | \ `.___.'\  _| |  \ \_  | \____) | 
#  `.____ .' |____||____| |________|  `.____ .' |____||____|  \______.' 
                                                                      
# deep inspection attribute will be included in each alert
configure do |c|
    c.deep_inspection   = [:id, :name, :status, :security_configuration, :security_configuration_details, :tags, :options]
end


def perform(aws)
  aws.emr.list_clusters[:clusters].each do | cluster |
    # Terminated EMR cluster stil shows up for ~2 weeks
    next if cluster[:status][:state].include?("TERMINAT")

    cluster_details = aws.emr.describe_cluster(cluster_id: cluster[:id])[:cluster]
    cluster_name = cluster_details[:name]
    set_data(cluster_details)

    if get_tag_matches(@options[:exclude_on_tag], cluster_details[:tags]).count > 0
      pass(message: "EMR cluster #{cluster_name} is excluded due to the tag", resource_id: cluster_details[:id])
      next
    end

    if cluster_details.key?("security_configuration") == false or cluster_details[:security_configuration] == ""
      set_data(security_configuration: nil)
      fail(message: "EMR cluster #{cluster_name} has no security configuration set", resource_id: cluster_details[:id])
      next
    end

    security_configuration = aws.emr.describe_security_configuration({name: cluster_details[:security_configuration]})[:security_configuration]
    security_configuration = JSON.parse(security_configuration) if security_configuration.is_a? String

    set_data(security_configuration_details: security_configuration)
    if security_configuration["EncryptionConfiguration"]["EnableInTransitEncryption"] and security_configuration["EncryptionConfiguration"]["EnableAtRestEncryption"]
      pass(message: "EMR cluster #{cluster_name} has both in-transit and at-rest encryption enabled", resource_id: cluster_details[:id])
    else
      if @options[:require_at_rest_encryption] and security_configuration["EncryptionConfiguration"]["EnableAtRestEncryption"] == false
        fail(message: "EMR cluster #{cluster_name} does not have at-rest encryption enabled", resource_id: cluster_details[:id])
      elsif @options[:require_in_transit_encryption] and security_configuration["EncryptionConfiguration"]["EnableInTransitEncryption"] == false
        fail(message: "EMR cluster #{cluster_name} does not have in-transit encryption enabled", resource_id: cluster_details[:id])
      else
        # Should not happen...
        fail(message: "EMR clsuter #{cluster_name} does not have in-transit or at-rest encryption enabled", resource_id: cluster_details[:id])
      end
    end

  end
end



# Return the number of matching tags if one of the tag key-value pair matches
def get_tag_matches(option_tags, aws_tags)
  matches = []

  option_tags.each do | option_tag |
    # If tag value is a string, do string comparison (with wildcard support)
    if option_tag[:value].is_a? String
      option_value = option_tag[:value].sub('*','.*')

      aws_tags.each do | aws_tag | 
        if @options[:case_insensitive]
          value_pattern = /^#{option_value}$/i
          matches.push(aws_tag) if option_tag[:key].downcase == aws_tag[:key].downcase and aws_tag[:value].match(value_pattern)
        else
          value_pattern = /^#{option_value}$/
          matches.push(aws_tag) if option_tag[:key] == aws_tag[:key] and aws_tag[:value].match(value_pattern)
        end          
      end

    # if tag value is an array, check if value is in the array
    else
      if @options[:case_insensitive]
        option_values = option_tag[:value].map(&:downcase)
      else
        option_values = option_tag[:value]
      end

      aws_tags.each do | aws_tag |
        if @options[:case_insensitive]
          matches.push(aws_tag) if (option_tag[:key].downcase == aws_tag[:key].downcase && (option_values.include?(aws_tag[:value].downcase)))
        else
          matches.push(aws_tag) if (option_tag[:key] == aws_tag[:key] && (option_values.include?(aws_tag[:value])))
        end
      end
    end
  end

  return matches
end