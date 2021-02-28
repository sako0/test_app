class ApplicationController < ActionController::Base
  # LINEクライアント設定
  # def client
  #   @client ||= Line::Bot::Client.new { |config|
  #     config.channel_id = ENV["LINE_CHANNEL_ID"]
  #     config.channel_secret = ENV['LINE_CHANNEL_SECRET']
  #     config.channel_token = ENV['LINE_CHANNEL_TOKEN']
  #   }
  #   @body = request.body.read
  #   @signature = request.env['HTTP_X_LINE_SIGNATURE']
  #   unless @client.validate_signature(@body, @signature)
  #     error 400 do
  #       'Bad Request'
  #     end
  #   end
  #   @line_header = {
  #     'Authorization' => "Bearer " + ENV['LINE_CHANNEL_TOKEN'],
  #     'Content-type' => 'application/json',
  #   }
  # end
end
