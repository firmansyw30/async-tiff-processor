import { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } from "@aws-sdk/client-sqs";
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { pipeline } from "stream/promises";
import 'dotenv/config';

const sqsClient = new SQSClient({ region: process.env.AWS_REGION });
const s3Client = new S3Client({ region: process.env.AWS_REGION });

const QUEUE_URL = process.env.SQS_QUEUE_URL;
const LOCAL_DIR = '/tmp/raster-data'; // The folder on EC2 where files are saved
const DOCKER_IMAGE = process.env.WORKER_DOCKER_IMAGE;

// Ensure the local directory exists
if (!fs.existsSync(LOCAL_DIR)) {
  fs.mkdirSync(LOCAL_DIR, { recursive: true });
}

async function processQueue() {
  console.log("Polling SQS for messages...");

  while (true) {
    let key = "unknown"; // Initialize key for error handling context
    let message = null; // Initialize message for error handling context

    try {
      // 1. Poll SQS (Long Polling)
      const { Messages } = await sqsClient.send(new ReceiveMessageCommand({
        QueueUrl: QUEUE_URL,
        MaxNumberOfMessages: 1,
        WaitTimeSeconds: 20, // Wait up to 20s for a message to arrive
      }));

      if (!Messages || Messages.length === 0) continue;

      message = Messages[0];
      const body = JSON.parse(message.Body);

      // Safely handle S3 Test Events or invalid messages
      if (body.Event === 's3:TestEvent' || !body.Records) {
        console.log("Received S3 Test Event or unknown format. Deleting...");
        await sqsClient.send(new DeleteMessageCommand({
          QueueUrl: QUEUE_URL,
          ReceiptHandle: message.ReceiptHandle
        }));
        continue; // Skip to the next message
      }

      // 2. Extract S3 Bucket and Key
      const bucket = body.Records[0].s3.bucket.name;
      key = body.Records[0].s3.object.key; // e.g., "uploads/123-sample.tif"
      const fileName = path.basename(key);       // e.g., "123-sample.tif"
      const localFilePath = path.join(LOCAL_DIR, fileName);

      console.log(`Downloading ${key} from ${bucket}...`);

      // 3. Download the file from S3 to EC2 local storage
      const s3Response = await s3Client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
      await pipeline(s3Response.Body, fs.createWriteStream(localFilePath));

      console.log(`Executing Docker for ${fileName}...`);

      // 4. Run your Docker container dynamically
      // We map LOCAL_DIR to /data in the container
      const dockerCommand = `docker run --rm -v ${LOCAL_DIR}:/data --pull=always ${DOCKER_IMAGE} /data/${fileName}`;

      try {
        // execSync will pause Node.js and wait for the Docker container to finish
        execSync(dockerCommand, { stdio: 'inherit' });
      } catch (dockerError) {
        // Catch Python crashes so the worker doesn't crash completely
        console.error(`Docker container failed for ${fileName}:`, dockerError.message);
        throw dockerError; // Throw to the outer try/catch so the SQS message is handled
      }

      console.log(`Docker finished. Uploading result to S3...`);

      // Extract the filename without extension for the output file
      const { name } = path.parse(fileName);
      // Define the output file name the Python script generates (the transparent version of the tif file)
      const outputFileName = `${name}_transparent.tif`;
      const outputFilePath = path.join(LOCAL_DIR, outputFileName);

      // Verify the Python script actually created the output file
      if (fs.existsSync(outputFilePath)) {
        const fileStream = fs.createReadStream(outputFilePath);
        
        await s3Client.send(new PutObjectCommand({
          Bucket: bucket,
          Key: `processed-tiff/${outputFileName}`, // Save to a DIFFERENT folder, into the same bucket that has event files
          Body: fileStream,
          ContentType: 'image/tiff'
        }));
        
        console.log(`Successfully uploaded ${outputFileName} to S3.`);
        
        console.log(`Executing gdal2tiles for ${outputFileName}...`);

        // Define the local folder where the PNG tiles will be generated
        const tileOutputDirName = `tiles_${name}`;
        const tileOutputDirPath = path.join(LOCAL_DIR, tileOutputDirName);

        // Run gdal2tiles using the SAME image, but override the entrypoint
        const dockerTilesCommand = `docker run --rm -v ${LOCAL_DIR}:/data --entrypoint python3 ${DOCKER_IMAGE} -m osgeo_utils.gdal2tiles --tiledriver=PNG --resampling=near -z 18-22 /data/${outputFileName} /data/${tileOutputDirName}`;

        try {
          execSync(dockerTilesCommand, { stdio: 'inherit' });
          console.log(`Tiles generated successfully in ${tileOutputDirPath}`);

          // Upload the entire directory of PNGs to S3 using AWS CLI sync
          // This automatically handles multi-threading and directory structures
          console.log(`Syncing tiles to S3...`);
          const s3SyncCommand = `aws s3 sync ${tileOutputDirPath} s3://${bucket}/processed-tiles/${name}/ --content-type "image/png"`;
          execSync(s3SyncCommand, { stdio: 'inherit' });
          
          console.log(`Successfully uploaded all tiles to s3://${bucket}/processed-tiles/${name}/`);

          // Clean up the generated tiles folder from EC2 storage
          fs.rmSync(tileOutputDirPath, { recursive: true, force: true });

        } catch (tileError) {
          console.error(`Failed during gdal2tiles or sync for ${outputFileName}:`, tileError.message);
          throw tileError; 
        }
        // --- ADDED HERE: Clean up the transparent output file now that gdal2tiles is done ---
        fs.unlinkSync(outputFilePath);
      } else {
        console.error(`Output file ${outputFileName} was not found!`);
      }

      // 5. Clean up the original input file
      fs.unlinkSync(localFilePath);

      // 6. Delete the SQS message so it isn't processed again
      await sqsClient.send(new DeleteMessageCommand({
        QueueUrl: QUEUE_URL,
        ReceiptHandle: message.ReceiptHandle
      }));

    } catch (error) {
      console.error("Error processing message:", error);
      // If an error occurs (e.g., Docker crashes), the message is NOT deleted from SQS.
      // SQS will automatically retry it after the Visibility Timeout.
      // If the file is missing from S3, delete the SQS message to break the infinite loop
      if (error.name === 'NoSuchKey') {
        console.log(`File ${key} no longer exists in S3. Deleting ghost message from SQS...`);
        try {
          await sqsClient.send(new DeleteMessageCommand({
            QueueUrl: QUEUE_URL,
            ReceiptHandle: message.ReceiptHandle
          }));
        } catch (deleteError) {
          console.error("Failed to delete ghost message:", deleteError);
        }
      }
    }
  }
}

processQueue();