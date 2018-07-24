require 'mechanize'
require 'scraperwiki'
require 'logger'

class Net::HTTP::Persistent
  module DisableSslReuse
    def connection_for(uri)
      connection = super
      connection.instance_variable_set(:@ssl_session, nil)
      return connection
    end
  end

  include DisableSslReuse   # https://qiita.com/yhara/items/01a999ddc81c037562d3
end


agent = Mechanize.new
agent.ssl_version = :SSLv3_server
enquiry_url = "https://epathway.thehills.nsw.gov.au/ePathway/Production/Web/GeneralEnquiry/EnquiryLists.aspx"

# Get the main page and ask for DAs

page = agent.get(enquiry_url)
form = page.forms.first
form.radiobuttons[0].click
page = form.submit(form.button_with(:value => /Next/))

# Search for the last 30 days
form = page.forms.first
form.radiobuttons.last.click
page = form.submit(form.button_with(:value => /Search/))

page_label = page.at('#ctl00_MainBodyContent_mPagingControl_pageNumberLabel')
if page_label.nil?
  # If we can't find the label assume there is only one page of results
  number_of_pages = 1
elsif page_label.inner_text =~ /Page \d+ of (\d+)/
  number_of_pages = $~[1].to_i
else
  raise "Unexpected form for number of pages"
end

puts "Found #{number_of_pages} pages of development applications"

(1..number_of_pages).each do |page_no|
  puts "Scraping page #{page_no}"
  # Don't refetch the first page
  if page_no > 1
    page = agent.get("https://epathway.thehills.nsw.gov.au/ePathway/Production/Web/GeneralEnquiry/EnquirySummaryView.aspx?PageNumber=#{page_no}")
  end

  # Extract applications
  page.at('table.ContentPanel').search('tr')[1..-1].each do |row|

    date_received = row.search(:td)[1].inner_text
    day, month, year = date_received.split("/").map{|s| s.to_i}

    record = {
      date_received:     Date.new(year, month, day).to_s,
      council_reference: row.search(:td)[0].inner_text,
      description:       row.search(:td)[2].inner_text,
      address:           row.search(:td)[3].inner_text,
      info_url:          enquiry_url,
      comment_url:       enquiry_url,
      date_scraped:      Date.today.to_s
    }

    if (ScraperWiki.select("* from data where `council_reference`='#{record[:council_reference]}'").empty? rescue true)
      ScraperWiki.save_sqlite([:council_reference], record)
    else
      puts "Skipping already saved record " + record[:council_reference]
    end
  end
end
