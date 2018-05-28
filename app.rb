require 'sinatra'
require 'line/bot'

require 'open-uri'
require 'nokogiri'

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def get_tour(lim)
  $tused ||= {}

  doc = Nokogiri::HTML(open("https://statsroyale.com/tournaments"))

  frac = doc.xpath('//div[starts-with(@class, "challenges__row")]').map do |el|
    u = el.children[0].text.split
    u.empty? || u[0][0] == ?# ? nil : u[0]
  end.compact

  seri = doc.xpath('//div[starts-with(@class, "challenges__row")]').map do |el|
    u = el.children[0].text.split
    u.empty? || u[0][0] != ?# ? nil : u[0]
  end.compact

  name = doc.xpath('//a[starts-with(@class, "ui__blueLink")]').map do |el|
    el.children[0].text
  end

  s = frac.zip(name.zip(seri)).map(&:flatten).map do |t|
    f, n, x = t
    a, b = f.split(?/).map &:to_i
    a == b || b < lim || (lim > 50 && $tused.include?(x)) ? nil : ($tused[x] = true; t.join(?:))
  end.compact.join(?\n)

  return 'No tournament found' if s.empty?
  s
end

$uids ||= {}

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    # error 400 do 'Bad Request' end
    t = get_tour(100)
    if t != 'No tournament found' 
      $uids.keys.each do |uid|
        message = {
          type: 'text',
          text: get_tour(100)
        }

        client.push_message(uid, message)
      end
    end
  else
    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          message = {
            type: 'text',
            text: get_tour(50)
          }
          $uids[event['source']['userId']] = true
          client.reply_message(event['replyToken'], message)
        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      else
      end
    }

    "OK"
  end

end
