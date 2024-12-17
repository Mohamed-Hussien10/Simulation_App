import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class ExcelParallelServerService {
  final List<List<dynamic>> _excelData;
  final List<List<dynamic>> _analysisData;
  final List<List<dynamic>> _newSimulationData;
  final int serverNum;
  static String? _savedFilePath;

  ExcelParallelServerService(this._excelData, this._analysisData,
      this._newSimulationData, this.serverNum);

  Future<void> saveExcelProbTables() async {
    // Request storage permission
    await _requestStoragePermission();

    // Create a new Excel workbook
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];

    // Define base headers
    final baseHeaders = ['Code', 'ServType', 'Prob', 'From', 'To'];
    List<String> headers = List.from(baseHeaders);

    // Add dynamic server columns based on `serverNum`
    for (int i = 1; i <= serverNum; i++) {
      headers.add('AvgDur S$i'); // Add headers for each server
    }

    // Define cell style for headers
    final headerStyle = workbook.styles.add('HeaderStyle');
    headerStyle.backColor = '#FFFF00'; // Yellow color
    headerStyle.hAlign = xlsio.HAlignType.center; // Center alignment
    headerStyle.bold = true; // Make headers bold

    // Set headers and apply style
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(18, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }

// Insert analysis data rows
    for (int i = 0; i < _analysisData.length; i++) {
      final row = _analysisData[i];
      for (int j = 0; j < row.length; j++) {
        final cell = sheet.getRangeByIndex(i + 19, j + 1);

        // Apply formulas for specific columns
        if (j == 2) {
          // Column "Probability" Formula (E.g., COUNTIF or other relevant logic)
          cell.setFormula(
              '==ROUND(COUNTIF(\$C\$2:\$C\$16,B${i + 19})/COUNT(\$A\$2:\$A\$16), 2)');
        } else if (j == 3) {
          // Column "From" is already calculated and set in data
          if (i != 0) {
            cell.setFormula('=ROUND(E${i + 18}+1, 0)');
          } else {
            cell.setNumber(double.parse(row[j].toString()));
          }
        } else if (j == 4) {
          // Column "To" is already calculated and set in data

          if (i != 0) {
            cell.setFormula('=ROUND(C${i + 19}*100+E${i + 18}, 0)');
          } else {
            cell.setFormula('=ROUND(C${i + 19}*100, 0)');
          }
        } else if (j >= 5) {
          // Average Duration Formula (for each server column)
          cell.setFormula(
              '=IFERROR(ROUND(SUMIFS(\$D\$2:\$D\$16,\$C\$2:\$C\$16,B${i + 19},\$E\$2:\$E\$16,"${(j - 5) + 1}")/COUNTIFS(\$C\$2:\$C\$16,B${i + 19},\$E\$2:\$E\$16,"${(j - 5) + 1}"), 0), 0)');
        } else {
          // For other columns, set the cell value directly
          if (row[j] is num || double.tryParse(row[j].toString()) != null) {
            cell.setNumber(double.parse(row[j].toString()));
          } else {
            cell.setText(row[j].toString());
          }
        }

        // Apply cell style
        cell.cellStyle.hAlign = xlsio.HAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      }
    }

    //===========================================================================================

    // Offset index for _excelData to start after the _analysisData table
    final excelDataHeaders = [
      'Cust_id',
      'Interval',
      'Service',
      'Duration',
      'Server'
    ];

    // Set excelDataHeaders and apply style
    for (int i = 0; i < excelDataHeaders.length; i++) {
      final cell = sheet.getRangeByIndex(1, 1 + i);
      cell.setText(excelDataHeaders[i]);
      cell.cellStyle = headerStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }

    // Insert _excelData to the right of _analysisData
    for (int i = 0; i < _excelData.length; i++) {
      final row = _excelData[i];
      for (int j = 0; j < row.length; j++) {
        final cell = sheet.getRangeByIndex(i + 2, 1 + j);

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

    //===========================================================================================
    // Leave a separator row and then add headers for Simulation Data
    // int simulationDataStartIndex = _analysisData.length + 3;
    // Define simulation headers dynamically based on the number of servers
    List<String> simulationHeaders = [
      'Cust_id',
      'Interval',
      'Arr.Clock',
      'Random',
      'Service',
      for (int i = 0; i < serverNum; i++) ...[
        'Start_S${i + 1}',
        'Duration_S${i + 1}',
        'End_S${i + 1}',
      ],
      'Cust.Wait',
    ];

// Define cell style for simulation headers
    final simulationHeaderStyle = workbook.styles.add('SimulationHeaderStyle');
    simulationHeaderStyle.backColor = '#FFFF00'; // Yellow color
    simulationHeaderStyle.hAlign = xlsio.HAlignType.center; // Center alignment
    simulationHeaderStyle.bold = true; // Make headers bold

// Set headers for simulation data and apply style
    for (int i = 0; i < simulationHeaders.length; i++) {
      final cell = sheet.getRangeByIndex(25, i + 1);
      cell.setText(simulationHeaders[i]);
      cell.cellStyle = simulationHeaderStyle; // Apply header style
      cell.cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin; // Add borders to header cells
    }
// Insert simulation data rows dynamically
    for (int i = 0; i < _newSimulationData.length; i++) {
      for (int j = 0; j < _newSimulationData[i].length; j++) {
        final cell = sheet.getRangeByIndex(26 + i, j + 1); // Adjust row index
        final data = _newSimulationData[i][j];

        if (data is String && data.trim().isEmpty) {
          cell.setText(' '); // Handle empty cells
        } else if (j == 1) {
          // Interval column
          cell.setFormula(
              '=RANDBETWEEN(MIN(\$B\$2:\$B\$16), MAX(\$B\$2:\$B\$16))');
        } else if (j == 2 && i != 0) {
          // Arrival Clock column
          cell.setFormula('=C${25 + i} + B${26 + i}');
        } else if (j == 3) {
          // Random value column
          cell.setFormula('=RANDBETWEEN(\$D\$19, \$E\$23)');
        } else if (j == 4) {
          // Service type column
          cell.setFormula(
              '=LOOKUP(D${26 + i}, \$D\$19:\$D\$23, \$B\$19:\$B\$23)');
        } else if (j >= 5 && j < (5 + 3 * serverNum)) {
          // Handle formulas for dynamic server columns
          int serverIndex = (j - 5) ~/ 3;
          int startColumn = 5 + serverIndex * 3;
          int durationColumn = startColumn + 1;
          int endColumn = startColumn + 2;

          if (j == startColumn) {
            // Start_S column
            if (j == 5) {
              if (i == 0) {
                cell.setFormula('=C26');
              } else {
                cell.setFormula(
                    '=IF(MAX(\$H\$26:H${25 + i})<MAX(\$K\$26:K${25 + i}), MAX(C${26 + i}, MAX(\$H\$26:H${25 + i})), "")');
              }
            } else {
              String previousServerStartLetter = String.fromCharCode(
                  (65 + (j - 1)) - 2); // 65 is ASCII for 'A'
              String currentServerEndLetter = String.fromCharCode(
                  (65 + (j - 1)) + 3); // 65 is ASCII for 'A'
              cell.setFormula(
                  '=IF($previousServerStartLetter${26 + i}<>"","",MAX(C${26 + i},MAX(\$$currentServerEndLetter\$26,$currentServerEndLetter${25 + i})))');
            }
          } else if (j == durationColumn) {
            // Duration_S column
            String currentServerStartLetter =
                String.fromCharCode(65 + (j - 1)); // 65 is ASCII for 'A'
            String serverAvrageDurtion =
                String.fromCharCode(69 + ((j ~/ 3) - 1)); // 65 is ASCII for 'A'
            cell.setFormula(
                '=IF($currentServerStartLetter${26 + i}<>"",LOOKUP(D${26 + i},\$D\$19:\$E\$23,\$$serverAvrageDurtion\$19:\$$serverAvrageDurtion\$23),"")');
          } else if (j == endColumn) {
            // Convert column number (1-based) to letter
            String currentColumnLetter =
                String.fromCharCode(65 + (j - 1)); // 65 is ASCII for 'A'
            String previousColumnLetter =
                String.fromCharCode(64 + (j - 1)); // Previous column letter

            // Set the formula dynamically
            String formula =
                '=$previousColumnLetter${26 + i} + $currentColumnLetter${26 + i}';
            cell.setFormula(formula);
          }
        } else {
          cell.setText(data?.toString() ?? '');
        }

        // Style each cell
        cell.cellStyle.hAlign = xlsio.HAlignType.center; // Center alignment
        cell.cellStyle.borders.all.lineStyle =
            xlsio.LineStyle.thin; // Add borders to data cells
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
