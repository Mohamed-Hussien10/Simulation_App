import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class ExcelProbService {
  final List<List<dynamic>> _excelData;
  final List<List<dynamic>> _analysisData;
  final List<List<dynamic>> _newSimulationData;
  static String? _savedFilePath;

  ExcelProbService(
      this._excelData, this._analysisData, this._newSimulationData);

  Future<void> saveExcelProbTables() async {
    // Request storage permission
    await _requestStoragePermission();

    // Create a new Excel workbook
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];

    // Set headers for Analysis Data
    final headers = [
      'Cust_id',
      'ServType',
      'Avg.Dur',
      'Prob',
      'Cum.Prob',
      'From',
      'To'
    ];

    // Define cell style for headers
    final headerStyle = workbook.styles.add('HeaderStyle');
    headerStyle.backColor = '#FFFF00'; // Yellow color
    headerStyle.hAlign = xlsio.HAlignType.center; // Center alignment
    headerStyle.bold = true; // Make headers bold

    // Set headers and apply style
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }

    // Insert analysis data rows if available
    for (int i = 0; i < _analysisData.length; i++) {
      final row = _analysisData[
          i]; // Ensure you're accessing _analysisData, not _excelData
      for (int j = 0; j < row.length; j++) {
        if (j < headers.length) {
          final cell = sheet.getRangeByIndex(i + 2, j + 1);

          // Check if the column is the first, third, fifth, sixth, or seventh column
          if (j == 0 || j == 2 || j == 3 || j == 4 || j == 5 || j == 6) {
            // Check if the value is numeric and set it as a number
            if (row[j] is num) {
              cell.setNumber(
                  (row[j] as num).toDouble()); // Insert as a number if numeric
            } else {
              // Convert string to a number if the value is a valid number as a string
              var parsedValue = double.tryParse(row[j].toString());
              if (parsedValue != null) {
                cell.setNumber(parsedValue); // Set the parsed value as a number
              } else {
                cell.setText(row[j].toString()); // Otherwise, set as text
              }
            }

            // Check if specific columns require formulas
            if (j == 2) {
              // Interval = SUMIF(\$N\$2:\$N\$16,B2,\$O\$2:\$O\$16)/COUNTIF(\$N\$2:\$N\$16,B2)
              cell.setFormula(
                  '=SUMIF(\$N\$2:\$N\$16,B${i + 2},\$O\$2:\$O\$16)/COUNTIF(\$N\$2:\$N\$16,B${i + 2})');
            } else if (j == 3 && i > 0) {
              // Probability = ROUND(COUNTIF(\$N\$2:\$N\$16,B${i + 1})/COUNT(\$L\$2:\$L\$16),2)
              cell.setFormula(
                  'ROUND(COUNTIF(\$N\$2:\$N\$16,B${i + 2})/COUNT(\$L\$2:\$L\$16),2)');
            } else if (j == 5 && i > 0) {
              // From = '=G${i + 1}+1'
              cell.setFormula('=G${i + 1}+1');
            } else if (j == 6) {
              if (i == 0) {
                // To = 'D${i + 1} * 100'
                cell.setFormula('=D${i + 2} * 100');
              } else {
                // To = 'D${i + 1} * 100'
                cell.setFormula('=D${i + 2} * 100 + G${i + 1}');
              }
            } else {
              // For other columns or non-formula cells, set value from _excelData
              if (row[j] is num) {
                cell.setNumber((row[j] as num).toDouble());
              } else {
                var parsedValue = double.tryParse(row[j].toString());
                if (parsedValue != null) {
                  cell.setNumber(parsedValue);
                } else {
                  cell.setText(row[j].toString());
                }
              }
            }
          } else {
            // For other columns, set as text (e.g., column headers or non-numeric data)
            cell.setText(row[j].toString());
          }

          // Apply cell style
          cell.cellStyle.hAlign =
              xlsio.HAlignType.center; // Center alignment for data cells
          cell.cellStyle.borders.all.lineStyle =
              xlsio.LineStyle.thin; // Add borders to data cells
        }
      }
    }

    // Offset index for _excelData to start after the _analysisData table
    const excelDataStartColumn = 12; // Start after the _analysisData columns

    final excelDataHeaders = [
      'Cust_id',
      'Interval',
      'Service',
      'Duration',
    ];

    // Set excelDataHeaders and apply style
    for (int i = 0; i < excelDataHeaders.length; i++) {
      final cell = sheet.getRangeByIndex(1, excelDataStartColumn + i);
      cell.setText(excelDataHeaders[i]);
      cell.cellStyle = headerStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }

    // Insert _excelData to the right of _analysisData
    for (int i = 0; i < _excelData.length; i++) {
      final row = _excelData[i];
      for (int j = 0; j < row.length; j++) {
        final cell = sheet.getRangeByIndex(i + 2, excelDataStartColumn + j);

        // Check if the column is the first, second, or fourth column
        if (j == 0 || j == 1 || j == 3) {
          // Check if the value is numeric and set it as a number
          if (row[j] is num) {
            cell.setNumber(
                (row[j] as num).toDouble()); // Insert as a number if numeric
          } else {
            // Convert string to a number if the value is a valid number as string
            var parsedValue = double.tryParse(row[j].toString());
            if (parsedValue != null) {
              cell.setNumber(parsedValue); // Set the parsed value as a number
            } else {
              cell.setText(row[j].toString()); // Otherwise, set as text
            }
          }
        } else {
          // For columns other than the first, second, and fourth, set as text
          cell.setText(row[j].toString());
        }

        // Apply cell style
        cell.cellStyle.hAlign = xlsio.HAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      }
    }

    // Leave a separator row and then add headers for Simulation Data
    int simulationDataStartIndex = _analysisData.length + 3;
    final simulationHeaders = [
      'Cust_id',
      'Interval',
      'Arr.Clock',
      'Code',
      'Service',
      'Start',
      'Duration',
      'End.Clock',
      'State',
      'Cust.Wait'
    ];

    // Define cell style for simulation headers
    final simulationHeaderStyle = workbook.styles.add('SimulationHeaderStyle');
    simulationHeaderStyle.backColor = '#FFFF00'; // Yellow color
    simulationHeaderStyle.hAlign = xlsio.HAlignType.center; // Center alignment
    simulationHeaderStyle.bold = true; // Make headers bold

    // Set headers for simulation data and apply style
    for (int i = 0; i < simulationHeaders.length; i++) {
      final cell = sheet.getRangeByIndex(simulationDataStartIndex, i + 1);
      cell.setText(simulationHeaders[i]);
      cell.cellStyle = simulationHeaderStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }

    // Insert simulation data rows if available
    for (int i = 0; i < _newSimulationData.length; i++) {
      for (int j = 0; j < _newSimulationData[i].length; j++) {
        if (j < simulationHeaders.length) {
          final cell =
              sheet.getRangeByIndex(simulationDataStartIndex + 1 + i, j + 1);
          // For columns that require formulas
          if (j == 1 && i > 0) {
            // Interval = Random between MIN(\$M\$2:\$M\$16) and MAX(\$M\$2:\$M\$16)
            cell.setFormula(
                '=RANDBETWEEN(MIN(\$M\$2:\$M\$16),MAX(\$M\$2:\$M\$16))');
          } else if (j == 2 && i > 0) {
            // Arr.Clock = current Interval + previous row's Arr.Clock
            cell.setFormula(
                '=B${simulationDataStartIndex + 1 + i} + C${simulationDataStartIndex + i}');
          } else if (j == 3) {
            // Code = Random between F2 : G6
            cell.setFormula('=RANDBETWEEN(\$F\$2,\$G\$6)');
          } else if (j == 4) {
            // Service = LOOKUP(D${i + 9},\$F\$2,\$G\$6,\$B\$2:\$B\$6)
            cell.setFormula(
                '=LOOKUP(D${simulationDataStartIndex + 1 + i},\$F\$2:\$G\$6,\$B\$2:\$B\$6)');
          } else if (j == 5 && i != 0) {
            // Start = Max of Arr.Clock and End_Clock
            cell.setFormula(
                '=MAX(C${simulationDataStartIndex + 1 + i}, H${simulationDataStartIndex + i})');
          } else if (j == 6) {
            // Duration = LOOKUP(D${i + 9},\$F\$2,\$G\$6,\$C\$2:\$C\$6)
            cell.setFormula(
                '=LOOKUP(D${simulationDataStartIndex + 1 + i},\$F\$2:\$G\$6,\$C\$2:\$C\$6)');
          } else if (j == 7) {
            // End_Clock = Start + Duration
            cell.setFormula(
                '=F${simulationDataStartIndex + 1 + i} + G${simulationDataStartIndex + 1 + i}');
          } else if (j == 8) {
            if (i == 0) {
              // Server State for the first row
              cell.setFormula(
                  '=IF(B${simulationDataStartIndex + 1 + i} > 0, "Wait", "Busy")');
            } else {
              // Server State = IF Start - End_Clock > 0, then "Wait", otherwise "Busy"
              cell.setFormula(
                  '=IF(F${simulationDataStartIndex + 1 + i} - H${simulationDataStartIndex + 1 + i} > 0, "Wait", "Busy")');
            }
          } else if (j == 9) {
            // Cust Wait = Start - Arr.Clock
            cell.setFormula(
                '=F${simulationDataStartIndex + 1 + i} - C${simulationDataStartIndex + 1 + i}');
          } else {
            // For non-formula cells, insert the data from _simulationTable
            cell.setText(_newSimulationData[i][j]?.toString() ?? '');
          }

          cell.cellStyle.hAlign =
              xlsio.HAlignType.center; // Center alignment for data cells
          cell.cellStyle.borders.all.lineStyle =
              xlsio.LineStyle.thin; // Add borders to data cells
        }
      }
    }

    // Save the workbook and dispose of it
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    // Save file in application documents directory
    final directory = await getApplicationDocumentsDirectory();
    final savedFile = File('${directory.path}/_events.xlsx');

    try {
      await savedFile.writeAsBytes(bytes);
      _savedFilePath = savedFile.path;

      if (kDebugMode) {
        print('Events saved to Excel at: $_savedFilePath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving Excel file: $e');
      }
    }
  }

  Future<void> _requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<void> openSavedFile() async {
    if (_savedFilePath != null) {
      final result = await OpenFile.open(_savedFilePath);
      if (result.message != 'Done') {
        if (kDebugMode) {
          print('Failed to open file: ${result.message}');
        }
      }
    } else {
      if (kDebugMode) {
        print('No file path available to open.');
      }
    }
  }

  String? get savedFilePath => _savedFilePath;
}
