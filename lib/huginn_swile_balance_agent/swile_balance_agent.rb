module Agents
  class SwileBalanceAgent < Agent
    include FormConfigurable

    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The huginn catalog agent checks the balance on Swile.

      `debug` is used to verbose mode.

      `bearer_token` is needed for auth.

      `client_id` is needed for auth.

      `refresh_token` is needed for auth (first launch).

      `api_key` is needed for auth.

      `changes_only` is only used to emit event about a currency's change.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "id": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
            "type": "meal_voucher",
            "label": "Titres-resto",
            "balance": {
              "text": "540,00 €",
              "value": 540
            },
            "giftType": null,
            "networks": [
              "meal_voucher_default_fr",
              "meal_voucher_restaurant_fr"
            ]
          }
    MD

    def default_options
      {
        'bearer_token' => '',
        'api_key' => '',
        'client_id' => '',
        'refresh_token' => '',
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
        'changes_only' => 'true'
      }
    end

    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :bearer_token, type: :string
    form_configurable :api_key, type: :string
    form_configurable :client_id, type: :string
    form_configurable :refresh_token, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :debug, type: :boolean

    def validate_options
      unless options['bearer_token'].present?
        errors.add(:base, "bearer_token is a required field")
      end

      unless options['api_key'].present?
        errors.add(:base, "api_key is a required field")
      end

      unless options['client_id'].present?
        errors.add(:base, "client_id is a required field")
      end

      unless options['refresh_token'].present?
        errors.add(:base, "refresh_token is a required field")
      end

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def check
      handle
    end

    private

    def refresh(token)

      uri = URI.parse("https://directory.swile.co/oauth/token")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authority"] = "directory.swile.co"
      request["X-Lunchr-App-Version"] = "0.1.0"
      request["Authorization"] = "Bearer #{interpolated['bearer_token']}"
      request["Accept-Language"] = "fr"
      request["X-Lunchr-Platform"] = "web"
      request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.93 Safari/537.36"
      request["X-Api-Key"] = interpolated['api_key']
      request["Accept"] = "*/*"
      request["Sec-Gpc"] = "1"
      request["Origin"] = "https://team.swile.co"
      request["Sec-Fetch-Site"] = "same-site"
      request["Sec-Fetch-Mode"] = "cors"
      request["Sec-Fetch-Dest"] = "empty"
      request["Referer"] = "https://team.swile.co/"
      request.body = JSON.dump({
        "client_id" => interpolated['client_id'],
        "grant_type" => "refresh_token",
        "refresh_token" => token
      })
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log "request status : #{response.code}"

      if interpolated['debug'] == 'true'
        log "response.body"
        log response.body
      end

      if response.is_a?(Net::HTTPSuccess)
        memory['last_refresh_token'] = response.body
      else
        log "refresh failed"
      end

    end

    def handle

      if "#{memory['last_refresh_token']}" == ''
        used_token = interpolated['refresh_token']
        bearer = interpolated['bearer_token']
        refresh(used_token)
        bearer = JSON.parse(memory['last_refresh_token'])['access_token']
      else
        used_token = JSON.parse(memory['last_refresh_token'])['refresh_token']
        refresh(used_token)
        bearer = JSON.parse(memory['last_refresh_token'])['access_token']
      end
      if interpolated['debug'] == 'true'
        log "used_token #{used_token}"
        log "bearer #{bearer}"
      end

      uri = URI.parse("https://neobank-api.swile.co/api/v0/wallets")
      request = Net::HTTP::Get.new(uri)
      request.content_type = "application/json"
      request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/112.0"
      request["Accept"] = "*/*"
      request["Accept-Language"] = "fr"
      request["Referer"] = "https://team.swile.co/"
      request["X-Lunchr-Platform"] = "web"
      request["Authorization"] = "Bearer #{bearer}"
      request["X-Api-Key"] = interpolated['api_key']
      request["Origin"] = "https://team.swile.co"
      request["Connection"] = "keep-alive"
      request["Sec-Fetch-Dest"] = "empty"
      request["Sec-Fetch-Mode"] = "cors"
      request["Sec-Fetch-Site"] = "same-site"
      request["Dnt"] = "1"
      request["Pragma"] = "no-cache"
      request["Cache-Control"] = "no-cache"
      request["Te"] = "trailers"
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log "request status : #{response.code}"

      if interpolated['debug'] == 'true'
        log "response.body"
        log response.body
      end

      payload = JSON.parse(response.body)

      if interpolated['debug'] == 'true'
        log "payload"
        log payload
      end

      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            payload["wallets"].each do |wallet|        
              create_event payload: wallet
            end
          else
            last_status = memory['last_status']
            if interpolated['debug'] == 'true'
              log "last_status"
              log last_status
            end

            payload["wallets"].each do |wallet|        
              found = false
              last_status["wallets"].each do |walletbis|
                if wallet["id"] == walletbis["id"] && wallet["balance"] == walletbis["balance"]
                  found = true
                  if interpolated['debug'] == 'true'
                    log "found is #{found}"
                  end
                end
              end
              if found == false
                create_event payload: wallet
              else
                if interpolated['debug'] == 'true'
                  log "found is #{found}"
                end
                
              end
            end
          end
          memory['last_status'] = payload
        else
          if interpolated['debug'] == 'true'
            log "no diff"
          end
        end
      else
        create_event payload: payload
        if payload != memory['last_status']
          memory['last_status'] = payload
        end
      end
    end
  end
end
