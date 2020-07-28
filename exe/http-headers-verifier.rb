#!/usr/bin/env ruby
require 'yaml'

require 'typhoeus'

require_relative '../lib/naive_cookie'
require_relative '../lib/http_headers_validations'
require_relative '../lib/http_headers_utils'

FILE_NAME_PREFIX = 'headers-rules-'
HTTP_TIMEOUT_IN_SECONDS = 3

if ARGV.length != 3 && ARGV.length != 2
    puts "usage: http-headers-verifier.rb [comma seperated policy names] [url] [?verbose]"
    exit 2
end

policy_arg, url, verbose = ARGV
@policies = policy_arg.split(',')

HttpHeadersUtils.verbose = !verbose.nil?

actual_headers = Typhoeus.get(url, timeout: HTTP_TIMEOUT_IN_SECONDS, followlocation: true).headers

def verify_headers!(actual_headers, rules)
    puts "Testing url: #{url}"
    puts "Starting verification of policies #{HttpHeadersUtils.bold(@policies.join(", "))}:"
    errors = []
    checked_already = Set.new
    rules[:headers].each do |expected_pair|
        expected_header = expected_pair.keys[0]
        expected_value = expected_pair[expected_header]
        actual_value = actual_headers[expected_header]
        checked_already.add(expected_header.downcase)
        epected_header_error = HttpHeadersValidations.assert_expected_header(expected_header, expected_value, actual_value)
        errors.push(epected_header_error)  unless epected_header_error.nil?
    end

    actual_headers.each do |expected_pair|
        actual_header, actual_value = expected_pair[0]
        next if checked_already.include? actual_header
        next if actual_header.downcase ==  'set-cookie'
        actual_value = actual_headers[actual_header]
        actual_header_errors = HttpHeadersValidations.assert_extra_header(actual_header, actual_value,
                                      rules[:ignored_headers], rules[:headers_to_avoid])
        errors.push(actual_header_errors)  unless actual_header_errors.nil?
    end

    unless actual_headers["set-cookie"].nil?
        [actual_headers["set-cookie"]].flatten.each do |cookie_str|
            parsed_cookie = NaiveCookie.new(cookie_str)
            error_text, failed = HttpHeadersValidations.assert_cookie_value(parsed_cookie, rules[:cookie_attr])
            errors.push(error_text) if failed
        end
    end

    if errors.compact.length > 0
        return false
    else
        return true
    end
end

def read_policies!(policy_files_names)
    settings = {headers: [], ignored_headers: [], cookie_attr: {}, headers_to_avoid: []}
    policy_files_names.each do |policy_name|
        policy_data = YAML.load_file("./#{FILE_NAME_PREFIX}#{policy_name}.yml")
        
        settings[:headers].push(policy_data['headers']) unless policy_data['headers'].nil?
        settings[:ignored_headers].push(policy_data['ignored_headers']) unless policy_data['ignored_headers'].nil?
        settings[:cookie_attr].merge!(policy_data['cookie_attr']) unless policy_data['cookie_attr'].nil?
        settings[:headers_to_avoid].push(policy_data['headers_to_avoid'])  unless policy_data['headers_to_avoid'].nil?
    end

    settings[:headers].flatten!
    settings[:ignored_headers] = settings[:ignored_headers].uniq.flatten.map(&:downcase)
    settings[:headers_to_avoid] = settings[:headers_to_avoid].uniq.flatten.map(&:downcase)

    return settings
end


if verify_headers!(actual_headers, read_policies!(@policies))
    puts "😎  Success !"
    exit 0
else
    puts "😱  Failed !"
    exit 1
end


