require "date"

module StrictDateParser
  def self.parse(data, format)
    return unless data.is_a?(String) && format.is_a?(String)

    parts = Date._strptime(data, format)
    return unless parts && complete_date?(parts)

    value = Date.strptime(data, format, Date::GREGORIAN)
    value if value.strftime(format) == data
  rescue Date::Error
    nil
  end

  def self.valid_format?(format)
    return false unless format.is_a?(String) && !format.empty?

    sample = Date.new(2000, 2, 29, Date::GREGORIAN).strftime(format)
    !parse(sample, format).nil?
  end

  def self.complete_date?(parts)
    (parts[:year] && parts[:mon] && parts[:mday]) ||
      (parts[:year] && parts[:yday]) ||
      (parts[:cwyear] && parts[:cweek] && parts[:cwday])
  end
  private_class_method :complete_date?
end
