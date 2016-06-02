#! /usr/bin/env ruby
# This scrapes unsplash.com

# Example API endpoints:
#
# https://unsplash.com/napi/photos/curated?page=3&per_page=12&order_by=latest
# https://unsplash.com/napi/photos?page=3&per_page=12&order_by=latest

require "rubygems" unless defined?(Gem)
require "bundler/setup"
Bundler.require(:default)

require "cgi"
require "digest"
require "pp"
require "net/http"

# Take the link header, and return a hash of links.
def parse_link_header header
  links = Hash.new
  parts = header.split(",")

  # Parse each part into a named link
  parts.each do |part, index|
    section = part.split(";")
    url = section[0][/<(.*)>/,1]
    name = section[1][/rel="(.*)"/,1].to_sym
    links[name] = URI(url)
  end
  return links
end

images = {}
path = "images"

# If an argument is passed, write images to there. Otherwise just write to an
# images folder.
if ARGV[0]
  path = ARGV[0]
end

# Until there are no more pages, iterate through every page and download the
# files.
page = 0
loop do
  # curl "https://unsplash.com/napi/photos?page=3&per_page=12&order_by=latest" \
  #  -H "authorization: Client-ID d69927c7ea5c770fa2ce9a2f1e3589bd896454f7068f689d8e41a25b54fa6042" \
  #  -H "accept-version: v1" --compressed
  params = {
    # https://unsplash.com/napi/photos?page=3&per_page=12&order_by=latest
    page: page,
    per_page: 12,
    order_by: "latest",
  }
  headers = {
    authorization: "Client-ID d69927c7ea5c770fa2ce9a2f1e3589bd896454f7068f689d8e41a25b54fa6042",
    "accept-version": "v1",
  }
  p params
  request = Typhoeus::Request.new("https://unsplash.com/napi/photos", method: :get, params: params, headers: headers)

  resp = request.run
  targets = parse_link_header(resp.headers["Link"])
  if targets[:next]
    page = CGI.parse(targets[:next].query)["page"][0]
  else
    exit
  end
  jsn = JSON.parse resp.response_body

  if jsn.is_a?(Hash) and jsn["error"]
    p jsn
    exit 1
  end

  jsn.each do |img|
    # Append new imgix params to get the image size I want.
    url = img["urls"]["full"] + "&fit=crop&w=1920&h=1200"
    filename = Digest::SHA256.hexdigest(url) + ".jpg"
    puts "#{url}\n\t-> #{filename}"
    url = URI(url)

    filepath = File.join(path, filename)
    if not File.exist?(filepath)
      Net::HTTP.start(url.host) do |http|
        f = open(filepath, "w")
        begin
          http.request_get(url) do |resp|
            resp.read_body do |segment|
              f.write(segment)
            end
          end
        ensure
          f.close()
        end
      end
    end
  end

  # Sleep just to be nice.
  sleep 0.3
end
