import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simulation_app/services/excel_parallel_server_service.dart';
import 'package:simulation_app/services/excel_prob_service.dart';
import 'dart:io';
import 'dart:math';

class ParallelServerSimulationScreen extends StatefulWidget {
  const ParallelServerSimulationScreen({super.key});

  @override
  _ExcelSimulationScreenState createState() => _ExcelSimulationScreenState();
}

class _ExcelSimulationScreenState
    extends State<ParallelServerSimulationScreen> {
  List<List<String>> excelData = [];
  List<List<String>> analysisData = [];
  List<List<String>> newSimulationData = [];
  bool isExcelLoaded = false;
  bool isExcelGenerated = false;
  bool isCleared = true;
  bool isExporting = false;
  String? _filePath = '';
  int customerNum = 1;
  static bool isDarkMode = false; // Track the current theme mode
  int serverNum = 2;
  late ExcelProbService service;
  final TextEditingController _custNumController = TextEditingController();
  final TextEditingController _serverNumController = TextEditingController();

  @override
  void initState() {
    super.initState();
    service = ExcelProbService(excelData, analysisData, newSimulationData);
    _loadDarkModePreference();
  }

  Future<void> _loadDarkModePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveDarkModePreference(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  Future<void> pickAndReadExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        _filePath = result.files.single.path;
        var bytes = File(_filePath!).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        if (excel.tables.isNotEmpty) {
          String firstTableName = excel.tables.keys.first;
          var rows = excel.tables[firstTableName]?.rows;

          if (rows != null && rows.isNotEmpty) {
            excelData = rows
                .skip(1)
                .map((row) =>
                    row.map((cell) => cell?.value?.toString() ?? '').toList())
                .toList();
            isExcelLoaded = true;
          } else {
            excelData = [
              ['Error:', 'The Excel sheet is empty or invalid.']
            ];
            isExcelLoaded = false;
          }
        }
      }
    } catch (e) {
      excelData = [
        ['Error:', e.toString()]
      ];
      isExcelLoaded = false;
    }
    setState(() {});
  }

  void updateExcelData() {
    // First, ensure that serverNum is up-to-date (e.g., from user input or default value)
    serverNum = int.tryParse(_serverNumController.text) ?? 2;

    Random random = Random();

    for (int rowIndex = 0; rowIndex < excelData.length; rowIndex++) {
      var row = excelData[rowIndex];

      int randomServerNumber = random.nextInt(serverNum) + 1;

      row[4] = '$randomServerNumber';

      excelData[rowIndex] = List.from(row);
    }

    setState(() {});
  }

  // Method to clear all data
  void clearAllTables() {
    setState(() {
      excelData.clear();
      analysisData.clear();
      newSimulationData.clear();
    });
  }

  void generateServiceAnalysis() {
    analysisData = [];
    Map<String, List<int>> serviceDurations = {}; // For all servers
    Map<String, int> serviceFrequency = {};
    serverNum = int.tryParse(_serverNumController.text) ??
        2; // Get the number of servers from user input
    double cumulativeProbability = 0;

    // Track all unique servers dynamically
    Set<String> servers = {};

    // Separate service durations by service-server dynamically
    for (var row in excelData) {
      String service = row[2]; // Service type
      int duration = int.tryParse(row[3]) ?? 0; // Duration
      String server = row[4]; // Server

      // Add the server to the set of unique servers
      servers.add(server);

      // Store durations separately for each service-server combination
      if (!serviceDurations.containsKey('$service-$server')) {
        serviceDurations['$service-$server'] = [];
      }
      serviceDurations['$service-$server']!.add(duration);

      // Track service frequency
      serviceFrequency[service] = (serviceFrequency[service] ?? 0) + 1;
    }

    int totalServices = serviceFrequency.values.fold(0, (a, b) => a + b);
    int previousTo = 0;
    int custIdCounter = 1;

    // Iterate over each service to generate analysis data
    serviceFrequency.forEach((service, _) {
      List<String> row = [];

      // Add the base columns
      row.add(custIdCounter.toString()); // Code
      row.add(service); // Service

      // Calculate the probability for the service
      double probability = serviceFrequency[service]! / totalServices;
      row.add(probability.toStringAsFixed(2)); // Probability

      // Add the cumulative range
      cumulativeProbability += probability;
      int to = (cumulativeProbability * 100).round();
      int from = analysisData.isEmpty ? 1 : previousTo + 1;
      row.add(from.toString()); // From
      row.add(to.toString()); // To

      // Add the average durations for each server dynamically based on serverNum
      List<int> durationsForAllServers = [];
      for (int i = 0; i < serverNum; i++) {
        String serverKey = '$service-${i + 1}';

        // Filter durations and calculate sum and count for the current server and service
        List<int> durations = serviceDurations[serverKey] ?? [];
        if (durations.isNotEmpty) {
          // Calculate SUMIFS equivalent (sum durations for the specific service and server)
          int sumOfDurations = durations.fold(0, (a, b) => a + b);

          // Calculate COUNTIFS equivalent (count occurrences for the specific service and server)
          int countOfDurations = durations.length;

          // Calculate average duration for the current service-server combination
          double averageDuration = countOfDurations > 0
              ? sumOfDurations / countOfDurations
              : 0; // Avoid division by zero

          durationsForAllServers
              .add(averageDuration.toInt()); // Add avg duration for this server
        } else {
          durationsForAllServers
              .add(0); // If no durations for the server, add 0
        }
      }

      // Add the dynamically calculated durations for each server
      for (var avgDuration in durationsForAllServers) {
        row.add(
            avgDuration.toStringAsFixed(2)); // Average duration for each server
      }

      // Add the row to the analysis data
      analysisData.add(row);

      previousTo = to;
      custIdCounter++;
    });

    setState(() {});
  }

  void generateNewSimulationTable() {
    newSimulationData = [];
    customerNum = int.tryParse(_custNumController.text) ?? 1;
    serverNum = int.tryParse(_serverNumController.text) ?? 2;

    // Initialize server end times
    List<double> serverEndTimes = List.filled(serverNum, 0.0);

    // Get the min and max values for the 'interval' column from the Excel data
    List<int> intervals = excelData.map((row) {
      return int.tryParse(row[1]) ?? 0;
    }).toList();
    int minInterval = intervals.reduce(min);
    int maxInterval = intervals.reduce(max);

    int previousArrivalClock = 0;

    for (int i = 0; i < customerNum; i++) {
      int custId = i + 1;

      // Generate interArrival time randomly between minInterval and maxInterval
      int interArrival =
          minInterval + Random().nextInt(maxInterval - minInterval + 1);

      // Calculate arrivalClock as an int value
      int arrivalClock =
          i == 0 ? interArrival : interArrival + previousArrivalClock;

      // Generate a random service code within 'From' and 'To' from analysisData
      int minCode = int.tryParse(analysisData.first[3]) ?? 0;
      int maxCode = int.tryParse(analysisData.last[4]) ?? 0;
      int code = minCode + Random().nextInt(maxCode - minCode + 1);

      // Find the service type and average duration based on the generated code
      String service = '';
      double avgDuration = 0.0;

      // Loop through analysisData to find the correct service and duration
      for (var row in analysisData) {
        int from = int.tryParse(row[3]) ?? 0;
        int to = int.tryParse(row[4]) ?? 0;

        // Check if the generated code is within the 'from' and 'to' range
        if (code >= from && code <= to) {
          service = row[1]; // Service type
          avgDuration = double.tryParse(row[5]) ??
              0.0; // Look for the corresponding duration value
          break;
        }
      }

      // Assign customer to the first available server
      int assignedServer = 0;
      double earliestEnd = serverEndTimes[0];
      for (int j = 1; j < serverNum; j++) {
        if (serverEndTimes[j] < earliestEnd) {
          assignedServer = j;
          earliestEnd = serverEndTimes[j];
        }
      }

      // Calculate start and end times for the assigned server
      double start =
          max(arrivalClock.toDouble(), serverEndTimes[assignedServer]);
      double end = start + avgDuration;

      // Calculate customer wait time (if negative, set to 0)
      double customerWait = start - arrivalClock;
      if (customerWait < 0) customerWait = 0;

      // Update the server's end time
      serverEndTimes[assignedServer] = end;

      // Add the simulation row to newSimulationData
      List<String> row = [
        custId.toString(),
        interArrival.toString(),
        arrivalClock.toString(),
        code.toString(),
        service,
      ];

      // Add Start, Duration, End for each server (if assigned)
      for (int j = 0; j < serverNum; j++) {
        if (assignedServer == j) {
          row.add(start.toStringAsFixed(1)); // Start time for this server
          row.add(avgDuration.toStringAsFixed(1)); // Duration for this server
          row.add(end.toStringAsFixed(1)); // End time for this server
        } else {
          row.add(
              " "); // Empty for other servers if the customer is not assigned
          row.add(" "); // Empty for other servers
          row.add(" "); // Empty for other servers
        }
      }

      // Add customer wait time to the row
      row.add(customerWait.toStringAsFixed(1));

      // Add this row to the newSimulationData
      newSimulationData.add(row);

      // Update previous arrival clock for the next iteration
      previousArrivalClock = arrivalClock;
    }

    setState(() {});
  }

  Widget buildFirstTable(
      List<List<String>> data, List<String> headers, int serverCount) {
    // Dynamically extend headers based on the number of servers
    List<String> headers = [
      'Cust_id',
      'Interval',
      'Service',
      'Duration',
      'Server',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          border: TableBorder.all(color: Colors.black),
          defaultColumnWidth: const FixedColumnWidth(100.0),
          children: [
            if (data.isNotEmpty)
              // Header row
              TableRow(
                  children: headers
                      .map((cell) => _buildCell(cell, isHeader: true))
                      .toList()),

            // Data rows
            ...data.map((row) {
              return TableRow(
                children: row.map((cell) => _buildCell(cell)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  //================================================================================================
  Widget buildSecondTable(
      List<List<String>> data, List<String> headers, int serverNum) {
    // Dynamically extend headers based on the number of servers
    List<String> dynamicHeaders = [
      'Code',
      'Service',
      'Prob.',
      'From',
      'To',
    ];

    // Add dynamic columns for each server
    for (int i = 0; i < serverNum; i++) {
      dynamicHeaders.add('Avg.Dur ${i + 1}'); // Updated to 'Avg.Dur(serverNum)'
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          border: TableBorder.all(color: Colors.black),
          defaultColumnWidth: const FixedColumnWidth(100.0),
          children: [
            // Header row
            TableRow(
              children: dynamicHeaders
                  .map((header) => _buildCell(header, isHeader: true))
                  .toList(),
            ),
            // Data rows with ensured uniform length
            ...data.map((row) {
              // Ensure the row length matches the header length
              List<String> paddedRow = List.from(row);

              // Pad the row with empty strings to match the header length
              while (paddedRow.length < dynamicHeaders.length) {
                paddedRow.add('');
              }

              return TableRow(
                children: paddedRow.map((cell) => _buildCell(cell)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  //================================================================================================
  Widget buildThirdTable(
      List<List<String>> data, List<String> headers, int serverNum) {
    // Dynamically extend headers based on the number of servers
    List<String> dynamicHeaders = [
      'Cust_id', // Customer ID
      'Interval', // Interval between arrivals
      'Arr.Clock', // Arrival Clock time
      'Rand.', // Random number for service code
      'Service', // Service type (e.g., Deposit, Inquiry)
    ];

    // Add dynamic columns for each server: Start, Duration, End for each server
    for (int i = 0; i < serverNum; i++) {
      dynamicHeaders.add('Start_(S${i + 1})');
      dynamicHeaders.add('Dur_(S${i + 1})');
      dynamicHeaders.add('End_(S${i + 1})');
    }

    dynamicHeaders.add('Cust.Wait'); // Customer wait time

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          border: TableBorder.all(color: Colors.black),
          defaultColumnWidth: const FixedColumnWidth(100.0),
          children: [
            // Header row
            TableRow(
              children: dynamicHeaders
                  .map((header) => _buildCell(header, isHeader: true))
                  .toList(),
            ),
            // Data rows with ensured uniform length
            ...data.map((row) {
              return TableRow(
                children: row.map((cell) => _buildCell(cell)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  //================================================================================================
  Widget _buildCell(String cell, {bool isHeader = false}) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: isHeader
          ? Colors.yellow
          : (isDarkMode ? Colors.grey[850] : Colors.white),
      child: Text(
        cell,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader
              ? Colors.black
              : (isDarkMode ? Colors.white : Colors.black),
        ),
      ),
    );
  }

  //================================================================================================
  Future<void> saveExcelProbTables() async {
    // Initialize the service with the latest data right before saving
    final service = ExcelParallelServerService(
        excelData, // Use updated excelData
        analysisData, // Use updated analysisData
        newSimulationData, // Use updated newSimulationData
        serverNum);
    await service.saveExcelProbTables();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDarkMode
          ? ThemeData.dark()
          : ThemeData.light(), // Set the theme based on the toggle
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Parallel Server Simulation',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true, // Center the title for a clean design
          elevation: 4, // Add shadow for depth
          actions: [
            Tooltip(
              // Add a tooltip for better UX
              message:
                  isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              child: IconButton(
                icon: AnimatedSwitcher(
                  // Add a smooth transition when icon changes
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return RotationTransition(
                      turns: animation,
                      child: child,
                    );
                  },
                  child: Icon(
                    isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    key: ValueKey<bool>(isDarkMode), // Ensure smooth animations
                    color: isDarkMode ? Colors.yellowAccent : Colors.black54,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    isDarkMode = !isDarkMode; // Toggle the theme mode
                    _saveDarkModePreference(isDarkMode);
                  });
                },
              ),
            ),
          ],
          backgroundColor: isDarkMode
              ? Colors.black
              : Colors.white, // Adjust background color
          iconTheme: IconThemeData(
            color: isDarkMode
                ? Colors.white
                : Colors.black, // Icon color based on mode
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _custNumController,
                        style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Enter Customer Number',
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          filled: true,
                          fillColor: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade200,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.cyanAccent
                                  : Colors.blueAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isCleared = true;
                        });
                        clearAllTables();
                      },
                      label: const Icon(
                        Icons.delete,
                        color: Colors.white,
                        size: 30.0,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, // Button color
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 12.0),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12.0), // Rounded corners
                        ),
                        elevation: 5, // Subtle elevation for depth
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.start, // Aligns items to the start
                  children: [
                    Expanded(
                      // Ensure the TextField takes available space
                      child: TextField(
                        controller: _serverNumController,
                        style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Enter Server Number',
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          filled: true,
                          fillColor: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade200,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDarkMode
                                  ? Colors.cyanAccent
                                  : Colors.blueAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: isCleared
                          ? () async {
                              updateExcelData();
                            }
                          : null,
                      label: const Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: 30.0,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, // Button color
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 12.0),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12.0), // Rounded corners
                        ),
                        elevation: 5, // Subtle elevation for depth
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center, // Center the buttons
                  children: [
                    ElevatedButton(
                      onPressed: pickAndReadExcelFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Choose Excel File',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      onPressed: () {
                        generateServiceAnalysis();
                        generateNewSimulationTable();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Run Simulation',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                if (isExcelLoaded)
                  if (isExcelLoaded) buildFirstTable(excelData, [], serverNum),
                const SizedBox(height: 20),
                if (analysisData.isNotEmpty)
                  Column(
                    children: [
                      const Text(
                        'Analysis Data Table',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      buildSecondTable(analysisData, [], serverNum),
                    ],
                  ),
                const SizedBox(height: 20),
                if (newSimulationData.isNotEmpty)
                  Column(
                    children: [
                      const Text(
                        'Simulation Data Table',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      buildThirdTable(
                        newSimulationData,
                        [], // Headers are dynamically created in the function
                        serverNum, // Number of servers
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                if (newSimulationData.isNotEmpty)
                  Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: isExporting
                                ? null // Disable button while exporting
                                : () async {
                                    setState(() {
                                      isExporting = true;
                                    });

                                    await saveExcelProbTables();

                                    setState(() {
                                      isExporting = false;
                                      isExcelGenerated = true;
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isExporting
                                ? const SizedBox(
                                    height:
                                        24, // Set the height of the circular indicator
                                    width:
                                        24, // Set the width of the circular indicator
                                    child: CircularProgressIndicator(
                                      color: Colors
                                          .white, // Adjust the indicator color to fit the theme
                                      strokeWidth:
                                          3, // Set the stroke width for a more refined look
                                    ),
                                  )
                                : const Text(
                                    'Export to Excel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          16, // Ensure the font size is appropriate for readability
                                      color: Colors
                                          .white, // Text color for light contrast
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: isExcelGenerated
                                ? () async {
                                    await service.openSavedFile();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text(
                              'Open Excel File',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
