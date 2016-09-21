class SeedDump
  module DumpMethods
    include Enumeration

    def dump(records, options = {})
      return nil if records.count == 0

      io = open_io(records, options)

      write_records_to_io(records, io, options)

      ensure
        io.close if io.present?
    end

    private

    def dump_record(record, options)
      attribute_strings = []
      # We select only string attribute names to avoid conflict
      # with the composite_primary_keys gem (it returns composite
      # primary key attribute names as hashes).
      record.attributes.select {|key| key.is_a?(String) }.each do |attribute, value|
        value = anonymize(attribute, value) if options[:anonymize][record.class.to_s.downcase]&.include?(attribute)
        attribute_strings << dump_attribute_new(attribute, value, options) unless options[:exclude].include?(attribute.to_sym)
      end

      open_character, close_character = options[:import] ? ['[', ']'] : ['{', '}']

      "#{open_character}#{attribute_strings.join(", ")}#{close_character}"
    end

    def dump_attribute_new(attribute, value, options)
      options[:import] ? value_to_s(value) : "#{attribute}: #{value_to_s(value)}"
    end

    def value_to_s(value)
      value = case value
              when BigDecimal, IPAddr
                value.to_s
              when Date, Time, DateTime
                value.to_s(:db)
              when Range
                range_to_string(value)
              else
                value
              end

      value.inspect
    end

    def range_to_string(object)
      from = object.begin.respond_to?(:infinite?) && object.begin.infinite? ? '' : object.begin
      to   = object.end.respond_to?(:infinite?) && object.end.infinite? ? '' : object.end
      "[#{from},#{to}#{object.exclude_end? ? ')' : ']'}"
    end

    def open_io(records, options)
      if options[:file].present?
        mode = options[:append] ? 'a+' : 'w+'
        File.open(options[:file], mode)
      else
        directory = "db/seeds"
        Dir.mkdir(directory) unless File.exists?(directory)
        File.new("#{directory}/#{records}.rb", 'w+')
      end
    end

    def write_records_to_io(records, io, options)
      options[:exclude] ||= [:id, :created_at, :updated_at]

      method = options[:import] ? 'import' : 'create!'
      io.write("#{model_for(records)}.#{method}(")
      if options[:import]
        io.write("[#{attribute_names(records, options).map {|name| name.to_sym.inspect}.join(', ')}], ")
      end
      io.write("[\n  ")

      enumeration_method = if records.is_a?(ActiveRecord::Relation) || records.is_a?(Class)
                             :active_record_enumeration
                           else
                             :enumerable_enumeration
                           end
      puts "#{records} records number: #{records.count}"

      progressbar = ProgressBar.create(title: "[#{records}]", format:'%t 8%bD %P%%', starting_at: 0, total: records.count)

      send(enumeration_method, records, io, progressbar, options) do |record_strings, last_batch|
        io.write(record_strings.join(",\n  "))

        io.write(",\n  ") unless last_batch
      end

      io.write("\n])\n")

      if options[:file].present?
        nil
      else
        io.rewind
        io.read
      end
    end

    def attribute_names(records, options)
      attribute_names = if records.is_a?(ActiveRecord::Relation) || records.is_a?(Class)
                          records.attribute_names
                        else
                          records[0].attribute_names
                        end

      attribute_names.select {|name| !options[:exclude].include?(name.to_sym)}
    end

    def model_for(records)
      if records.is_a?(Class)
        records
      elsif records.respond_to?(:model)
        records.model
      else
        records[0].class
      end
    end

    def anonymize(attribute, value)
      if %w(email lead_emails unconfirmed_email).include?(attribute)
        value.split(',').map{|e| e.gsub(Devise.email_regexp) {"#{encode_string($1, 'x')}@#{$2}#{$3}"} }.join(',') if value.present?
      elsif %w(phone phone_number mobile_phone virtual_phone office_phone).include?(attribute)
        encode_string(value, '0')
      else
        encode_string(value, 'x')
      end
    end

    def encode_string(string, symbol)
      string&.gsub(/(.)./) {"#{$1}#{symbol}"}
    end
  end
end
