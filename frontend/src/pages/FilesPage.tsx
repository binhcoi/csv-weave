import { Badge, Button, Group, Stack, Table, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconUpload } from '@tabler/icons-react'
import PreviewNote from '../components/PreviewNote'

const operationColors: Record<string, string> = {
  Validation: 'grape',
  Conversion: 'blue',
}

const statusColors: Record<string, string> = {
  Completed: 'teal',
  Running: 'yellow',
  Failed: 'red',
}

const exampleRuns = [
  {
    id: 1,
    file: 'customers-may.csv',
    fileType: 'Customer import',
    operation: 'Conversion',
    status: 'Completed',
    accepted: 4821,
    rejected: 37,
  },
  {
    id: 2,
    file: 'customers-june.csv',
    fileType: 'Customer import',
    operation: 'Validation',
    status: 'Running',
    accepted: null,
    rejected: null,
  },
  {
    id: 3,
    file: 'orders-q2.csv',
    fileType: 'Order lines',
    operation: 'Conversion',
    status: 'Failed',
    accepted: null,
    rejected: null,
  },
]

function FilesPage() {
  useDocumentTitle('Files and runs · CSVWeave')

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Title order={1}>Files and runs</Title>
        <Button leftSection={<IconUpload size={16} />} disabled>
          Upload CSV
        </Button>
      </Group>
      <Text c="dimmed" maw="42rem">
        Upload a CSV for a file type, then validate it on its own or convert it with a compatible
        map. Runs execute in the background; results and rejection reports are downloadable here.
      </Text>
      <PreviewNote>
        Example data to settle the look and feel. Uploads and runs arrive once the shell is
        connected to the API.
      </PreviewNote>
      <Table striped highlightOnHover withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>File</Table.Th>
            <Table.Th>File type</Table.Th>
            <Table.Th>Operation</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Accepted</Table.Th>
            <Table.Th>Rejected</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {exampleRuns.map((run) => (
            <Table.Tr key={run.id}>
              <Table.Td fw={600}>{run.file}</Table.Td>
              <Table.Td>{run.fileType}</Table.Td>
              <Table.Td>
                <Badge variant="light" color={operationColors[run.operation]}>
                  {run.operation}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Badge variant="light" color={statusColors[run.status]}>
                  {run.status}
                </Badge>
              </Table.Td>
              <Table.Td>{run.accepted ?? '—'}</Table.Td>
              <Table.Td>{run.rejected ?? '—'}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Stack>
  )
}

export default FilesPage
