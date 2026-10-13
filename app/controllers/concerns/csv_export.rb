# encoding: UTF-8

# One way out for every CSV, so no export leaves the admin unrecorded.
module CsvExport
  private

  def send_csv(data, filename:, detail: nil)
    ExportRequest.record(data, path: request.fullpath, filename: filename, detail: detail)
    send_data data, filename: filename, type: "text/csv"
  end
end
