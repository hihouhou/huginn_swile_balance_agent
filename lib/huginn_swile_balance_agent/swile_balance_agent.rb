module Agents
  class SwileBalanceAgent < Agent
    include FormConfigurable

    can_dry_run!
    no_bulk_receive!
    default_schedule '1h'

    description do
      <<-MD
      The huginn catalog agent checks the balance on Swile.

      `debug` is used to verbose mode.

      `bearer_token` is needed for auth.

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
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
        'changes_only' => 'true'
      }
    end

    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :bearer_token, type: :string
    form_configurable :api_key, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :debug, type: :boolean

    def validate_options
      unless options['bearer_token'].present?
        errors.add(:base, "bearer_token is a required field")
      end

      unless options['api_key'].present?
        errors.add(:base, "api_key is a required field")
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

    def handle

      uri = URI.parse("https://bff-api.swile.co/graphql")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authority"] = "bff-api.swile.co"
      request["X-Lunchr-App-Version"] = "0.1.0"
      request["Authorization"] = "Bearer #{interpolated['bearer_token']}"
      request["X-Lunchr-Platform"] = "web"
      request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.72 Safari/537.36"
      request["X-Api-Key"] = interpolated['api_key']
      request["Accept"] = "*/*"
      request["Sec-Gpc"] = "1"
      request["Origin"] = "https://team.swile.co"
      request["Sec-Fetch-Site"] = "same-site"
      request["Sec-Fetch-Mode"] = "cors"
      request["Sec-Fetch-Dest"] = "empty"
      request["Referer"] = "https://team.swile.co/"
      request["Accept-Language"] = "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7"
      request.body = JSON.dump({
        "query" => "{
          walletsOverview {
            id
            type
            label
            balance {
              text
              value
            }
            giftType
            networks
          }
        }"
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

      payload = JSON.parse(response.body)

      if interpolated['debug'] == 'true'
        log "payload"
        log payload
      end

      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            payload["data"]["walletsOverview"].each do |wallet|        
              create_event payload: wallet
            end
          else
            last_status = memory['last_status'].gsub("=>", ": ").gsub(": nil", ": null")
            last_status = JSON.parse(last_status)

            if interpolated['debug'] == 'true'
              log "last_status"
              log last_status
            end

            payload["data"]["walletsOverview"].each do |wallet|        
              found = false
              last_status["data"]["walletsOverview"].each do |walletbis|
                if wallet == walletbis
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
          memory['last_status'] = payload.to_s
        else
            if interpolated['debug'] == 'true'
              log "no diff"
            end
        end
      else
        create_event payload: payload
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
