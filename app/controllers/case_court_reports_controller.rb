# frozen_string_literal: true

class CaseCourtReportsController < ApplicationController
  before_action :set_casa_case, only: %i[show]
  after_action :verify_authorized

  # GET /case_court_reports
  def index
    authorize CaseCourtReport
    @assigned_cases = CasaCase.actively_assigned_to(current_user)
      .select(:id, :case_number, :transition_aged_youth)
  end

  # GET /case_court_reports/:id
  def show
    authorize CaseCourtReport
    if !@casa_case || !@casa_case.court_report.attached?
      flash[:alert] = "Report #{params[:id]} is not found."
      redirect_to(case_court_reports_path) and return # rubocop:disable Style/AndOr
    end

    respond_to do |format|
      format.docx do
        @casa_case.court_report.open do |file|
          # TODO test this .read being present, we've broken it twice now
          send_data File.open(file.path).read, type: :docx, disposition: "attachment", status: :ok
        end
      end
    end
  end

  # POST /case_court_reports
  def generate
    authorize CaseCourtReport
    casa_case = CasaCase.find_by(case_params)
    respond_to do |format|
      format.json do
        if casa_case
          report_data = generate_report_to_string(casa_case)
          save_report(report_data, casa_case)

          render json: {link: case_court_report_path(casa_case.case_number, format: "docx"), status: :ok}
        else
          flash[:alert] = "Report #{params[:case_number]} is not found."
          error_messages = render_to_string partial: "layouts/flash_messages", formats: :html, layout: false, locals: flash
          flash.discard

          render json: {link: "", status: :not_found, error_messages: error_messages}, status: :not_found
        end
      end
    end
  end

  private

  def case_params
    params.require(:case_court_report).permit(:case_number)
  end

  def set_casa_case
    @casa_case = CasaCase.find_by(case_number: params[:id])
  end

  def generate_report_to_string(casa_case)
    return unless casa_case

    type = report_type(casa_case)
    court_report = CaseCourtReport.new(
      volunteer_id: current_user.id, # ??? not a volunteer ? linda
      case_id: casa_case.id,
      path_to_template: path_to_template(type)
    )
    court_report.generate_to_string
  end

  def save_report(report_data, casa_case)
    Tempfile.create do |t|
      t.binmode.write(report_data)
      t.rewind
      casa_case.court_report.attach(
        io: File.open(t.path), filename: "#{casa_case.case_number}.docx"
      )
    end
  end

  def report_type(casa_case)
    casa_case.has_transitioned? ? "transition" : "non_transition"
  end

  def path_to_template(type)
    "app/documents/templates/report_template_#{type}.docx"
  end
end
