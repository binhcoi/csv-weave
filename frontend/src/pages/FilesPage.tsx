import { Badge, Button, Group, Stack, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconUpload } from '@tabler/icons-react'
import Collection, { type CollectionField } from '../components/Collection'
import PreviewNote from '../components/PreviewNote'

interface ExampleRun {
  id: number
  file: string
  fileType: string
  operation: 'Validation' | 'Conversion'
  status: 'Completed' | 'Running' | 'Failed'
  accepted: number | null
  rejected: number | null
}

const operationColors = {
  Validation: 'grape',
  Conversion: 'blue',
} as const

const statusColors = {
  Completed: 'teal',
  Running: 'yellow',
  Failed: 'red',
} as const

const exampleRuns: ExampleRun[] = [
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

const fields: CollectionField<ExampleRun>[] = [
  { key: 'file', label: 'File', render: (run) => run.file },
  { key: 'fileType', label: 'File type', render: (run) => run.fileType },
  {
    key: 'operation',
    label: 'Operation',
    render: (run) => (
      <Badge variant="light" color={operationColors[run.operation]}>
        {run.operation}
      </Badge>
    ),
  },
  {
    key: 'status',
    label: 'Status',
    render: (run) => (
      <Badge variant="light" color={statusColors[run.status]}>
        {run.status}
      </Badge>
    ),
  },
  { key: 'accepted', label: 'Accepted', render: (run) => run.accepted ?? '—' },
  { key: 'rejected', label: 'Rejected', render: (run) => run.rejected ?? '—' },
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
      <Collection items={exampleRuns} fields={fields} itemKey={(run) => run.id} />
    </Stack>
  )
}

export default FilesPage
